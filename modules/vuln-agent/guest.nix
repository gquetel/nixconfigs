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
  claude-code = pkgs.callPackage ../../packages/claude-code { };
  workDir = "/work";
  stateDir = "${workDir}/state";
  secretsEnvFile = "/run/host-secrets/vuln-agent.env";

  # ExecCondition ($1 = %i): skip a nightly start while a manual run is active,
  # so manual always wins. The manual instance always proceeds.
  execCondition = pkgs.writeShellScript "vuln-agent-execcond" ''
    if [ "$1" = "nightly" ] && ${pkgs.systemd}/bin/systemctl is-active --quiet vuln-agent@manual.service; then
      echo "manual session active; skipping nightly start"
      exit 1
    fi
    exit 0
  '';
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
    # from, and agent-built paths land in a read-write upper layer.
    # That upper layer is disk-backed by the nix-cache share below and wiped every night.
    writableStoreOverlay = "/nix/.rw-store";
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

  # Trust the internal step-ca root ("garmr Root CA") so the agent can reach
  # mesh services (plane.mesh.gq, ca.mesh.gq, …) over TLS without -k. Same root
  # the rest of the fleet trusts via modules/common; the guest doesn't import
  # common, so wire it in directly.
  security.pki.certificates = [
    # From: http://ca.mesh.gq/roots.pem
    (builtins.readFile ../step-ca/roots.pem)
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
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

  # The runner, templated on mode (`%i` = nightly|manual). Started on demand:
  # @nightly by the 23:00 timer, @manual by the control poller on an operator trigger.
  systemd.services."vuln-agent@" = {
    description = "Autonomous vulnerability-research runner (%i)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      claude-code
      git
      curl
      jq
      docker
      nixos-container
      nix
    ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = workDir;
      EnvironmentFile = secretsEnvFile;

      # nightly: 23:00 -> 04:00 window (resets the 5h usage window by ~09:00).
      # manual: a 60-min wall-clock box.
      Environment = [
        "VA_MODE=%i"
        "VA_NIGHT_START=23:00"
        "VA_CUTOFF=04:00"
        "VA_MANUAL_MIN=60"
      ];
      # A nightly session yields to an in-progress manual run (manual preempts).
      ExecCondition = "${execCondition} %i";
      # Give a pre-accepted ~/.claude.json each start to prevent headless hangs.
      ExecStartPre = [
        "${pkgs.coreutils}/bin/install -m0644 ${./../plane/CLAUDE.md} ${workDir}/CLAUDE.md"
        "${pkgs.coreutils}/bin/install -m0600 ${./claude.json} ${workDir}/.claude.json"
      ];
      ExecStart = "${pkgs.python3}/bin/python3 ${./shim.py}";
      StandardOutput = "append:${stateDir}/agent.log";
      StandardError = "inherit";
      RuntimeMaxSec = "6h";  # backstop; the shim's STOP_AT ends it well before
      Restart = "no";
    };
  };

  # Nightly auto-start at 23:00. The shim's STOP_AT ends the session at 04:00.
  systemd.timers.vuln-agent-nightly = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:00:00";
      Unit = "vuln-agent@nightly.service";
      Persistent = false;
    };
  };

  # Control poller: 30s poll of the state dir for operator triggers. Polling
  # (not a .path unit) because inotify doesn't see host-side virtiofs writes.
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
    path = with pkgs; [ systemd coreutils ];
    script = ''
      S=${stateDir}
      # manual request -> stage prompt, preempt nightly, start manual, consume trigger.
      if [ -e "$S/manual.trigger" ]; then
        if ! systemctl is-active --quiet vuln-agent@manual.service; then
          cp -f "$S/manual.trigger" "$S/manual.prompt"
          systemctl stop vuln-agent@nightly.service 2>/dev/null || true
          systemctl start --no-block vuln-agent@manual.service
        fi
        rm -f "$S/manual.trigger"
      fi
      # stop request -> end whichever session is running.
      if [ -e "$S/stop.trigger" ]; then
        systemctl stop vuln-agent@manual.service vuln-agent@nightly.service 2>/dev/null || true
        rm -f "$S/stop.trigger"
      fi
    '';
  };
}
