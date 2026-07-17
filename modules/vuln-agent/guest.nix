# Guest NixOS config for the vulnerability-research microVM.
{
  config,
  lib,
  pkgs,
  inputs,
  vmName ? "vuln-agent",
  vcpu,
  mem,
  ...
}:
let
  llmAgents = pkgs.callPackage ../../packages/llm-agents {
    inherit inputs;
  };
  claude-code = llmAgents."claude-code";
  workDir = "/work";
  stateDir = "${workDir}/state";
  secretsEnvFile = "/run/host-secrets/vuln-agent.env";
  agentRuntime = inputs.vuln-agent-runtime;

  # Some designe requirements for the agent:
  # - Run during the night during 23 and 04:00
  # - Run manual runs that run for an hour during any time of the day
  # - Precedence of manual run over nightly ones (nightly ones are trigerred after)

  # We prevent the nightly start if a manual is already active
  nightlyGuard = pkgs.writeShellScript "vuln-agent-nightly-guard" ''
    if ${pkgs.systemd}/bin/systemctl is-active --quiet vuln-agent-manual.service; then
      echo "manual session active; skipping nightly start" >&2
      exit 1
    fi
    exit 0
  '';

  resumeNightly = pkgs.writeShellScript "vuln-agent-resume-nightly" ''
    if [ -e "${stateDir}/stop.trigger" ]; then
      exit 0
    fi
    ${pkgs.systemd}/bin/systemctl start --no-block vuln-agent-nightly.service
  '';

  mkRunner =
    {
      mode,
      runArgs,
      extraServiceConfig ? { },
    }:
    {
      description = "Autonomous vulnerability-research runner (${mode})";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [
        claude-code
        git
        curl
        jq
        python3
        docker
        nixos-container
        nix
        gawk
        which
        ripgrep
      ];
      serviceConfig = {
        Type = "simple";
        User = "agent";
        WorkingDirectory = workDir;
        EnvironmentFile = secretsEnvFile;
        ExecStartPre = [
          "${pkgs.coreutils}/bin/install -m0644 ${agentRuntime}/CLAUDE.md ${workDir}/CLAUDE.md"
          "${pkgs.coreutils}/bin/install -m0600 ${agentRuntime}/claude.json ${workDir}/.claude.json"
        ];
        ExecStart = "${pkgs.python3}/bin/python3 ${agentRuntime}/vuln_agent.py run --mode ${mode} ${runArgs}";
        StandardOutput = "append:${stateDir}/agent.log";
        StandardError = "inherit";
        RuntimeMaxSec = "6h";
        Restart = "on-failure";
        RestartSec = "30s";
        # if it crashes 5x within 10 min, something is most likely broken, we give up.
        StartLimitIntervalSec = "10min";
        StartLimitBurst = 5;
      }
      // extraServiceConfig;
    };
in
{
  # --------------------------- microVM shell -------------------------------- #
  microvm = {
    hypervisor = "qemu";
    inherit vcpu mem;

    interfaces = [
      {
        type = "tap";
        id = "vm-${vmName}";
        mac = "02:00:00:00:aa:01";
      }
    ];

    # Regarding /nix/store,  a read-only lower layer holds the store the VM boots
    # from, and agent-built paths land in a read-write 50GB upper layer.
    writableStoreOverlay = "/nix/.rw-store";

    volumes = [
      {
        image = "/var/lib/vuln-agent/disk/root.img";
        mountPoint = "/";
        label = "root";
        fsType = "ext4";
        size = 51200;
      }
    ];

    shares = [
      {
        source = "/var/lib/vuln-agent/nix-store";
        mountPoint = "/nix/.rw-store";
        tag = "nix-cache";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/state";
        mountPoint = stateDir;
        tag = "state";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/secrets";
        mountPoint = "/run/host-secrets";
        tag = "secrets";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tsstate";
        proto = "virtiofs";
      }
    ];
  };

  # Guest system basic config
  system.stateVersion = "25.05";
  networking.hostName = vmName;
  time.timeZone = "Europe/Paris";
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network = {
    enable = true;
    networks."10-uplink" = {
      matchConfig.MACAddress = "02:00:00:00:aa:01";
      address = [ "10.77.0.2/24" ];
      routes = [ { Gateway = "10.77.0.1"; } ];
      dns = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      linkConfig.RequiredForOnline = "routable";
    };
  };
  services.resolved.enable = true;

  # Trust the internal step-ca root CA.
  security.pki.certificates = [
    (builtins.readFile ../step-ca/roots.pem)
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    trusted-users = [
      "root"
      "agent"
    ];
  };

  # nixos-container support + KVM for nixosTest VMs
  boot.enableContainers = true;
  boot.kernelModules = [ "kvm-intel" ];
  virtualisation.docker.enable = true; # PoC fallback

  services.tailscale = {
    enable = true;
    authKeyFile = "/run/host-secrets/tailscale.authkey";
    extraUpFlags = [
      "--login-server"
      "https://mesh.gquetel.fr"
    ];
  };

  users.users.agent = {
    isNormalUser = true;
    home = workDir;
    createHome = true;
    extraGroups = [
      "docker"
      "wheel"
    ];
  };

  environment.systemPackages = with pkgs; [
    claude-code
    git
    curl
    jq
    python3
    nixos-container
  ];

  systemd.services.vuln-agent-nightly = mkRunner {
    mode = "nightly";
    runArgs = "--night-start 23:00 --cutoff 04:00";
    extraServiceConfig.ExecCondition = "${nightlyGuard}";
  };
  systemd.services.vuln-agent-manual = mkRunner {
    mode = "manual";
    runArgs = "--manual-min 60";
    # On stop, hand the remaining night window back to nightly
    extraServiceConfig.ExecStopPost = "+${resumeNightly}";
  };

  systemd.timers.vuln-agent-nightly = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:00:00";
      Unit = "vuln-agent-nightly.service";
      Persistent = false;
    };
  };

  systemd.timers.vuln-agent-control = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      Unit = "vuln-agent-control.service";
    };
  };
  systemd.services.vuln-agent-control = {
    description = "Poll the shared state dir for operator run/stop triggers";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      systemd
      coreutils
    ];
    script = ''
      S=${stateDir}
      # manual request -> stage prompt, preempt nightly, start manual, consume trigger.
      if [ -e "$S/manual.trigger" ]; then
        if ! systemctl is-active --quiet vuln-agent-manual.service; then
          cp -f "$S/manual.trigger" "$S/manual.prompt"
          systemctl stop vuln-agent-nightly.service 2>/dev/null || true
          systemctl start --no-block vuln-agent-manual.service
        fi
        rm -f "$S/manual.trigger"
      fi
      # stop request -> end whichever session is running.
      if [ -e "$S/stop.trigger" ]; then
        systemctl stop vuln-agent-manual.service vuln-agent-nightly.service 2>/dev/null || true
        rm -f "$S/stop.trigger"
      fi
    '';
  };
}
