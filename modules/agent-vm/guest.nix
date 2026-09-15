{
  lib,
  pkgs,
  vmName,
  tapName,
  baseDir,
  agentUid,
  vmIp,
  launcherName,
  mem,
  disk,
  ...
}:
# The system inside the VM.
#
# An ordinary machine with nix, docker, tmux and ssh, plus the launcher that
# starts one agent session. The host `agent-run` CLI is the front end; you can
# also run the launcher by hand:
#
#   ssh agent@<vm>               (or `ssh agent@10.77.0.2` from the host)
#   agent-session <profile> [driver option...] [--] [prompt...]
let
  workDir = "/work";

  # The runtime repo: the driver and the per-project profiles. It is cloned
  # here and not packaged, so a change to a profile needs a `git push` only.
  runtimeDir = "${workDir}/state/agent-runtime";

  claude-code = pkgs.callPackage ../../packages/claude-code { };

  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = with pkgs; [
      claude-code
      coreutils
      git
      python3
    ];
    text = ''
      if [ "$#" -lt 1 ]; then
        echo "usage: ${launcherName} <profile> [driver option...] [--] [prompt...]" >&2
        exit 2
      fi
      profile="$1"
      shift

      # Options after the profile go to the driver as they are, so a new driver
      # option needs no change here. An option takes the next word as its value
      # if that word does not start with `-`. The first other word starts the
      # prompt; `--` starts it too, for a prompt that starts with a dash.
      opts=()
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          --*=*) opts+=("$1"); shift ;;
          --*)
            opts+=("$1"); shift
            if [ "$#" -gt 0 ] && [ "''${1#-}" = "$1" ]; then
              opts+=("$1"); shift
            fi
            ;;
          *) break ;;
        esac
      done

      # ssh runs a command without a login shell, so nothing has read the keys
      # yet. AGENT_RUNTIME_TOKEN comes from here.
      set -a
      # shellcheck disable=SC1091
      . /run/agent-secrets/env
      set +a

      # The token is part of the URL, and it expires. Write it again on every
      # run, or the clone keeps the one it was made with.
      url="https://x-access-token:$AGENT_RUNTIME_TOKEN@github.com/gquetel/agent-runtime"
      if [ -d ${runtimeDir}/.git ]; then
        git -C ${runtimeDir} remote set-url origin "$url"
        git -C ${runtimeDir} pull --ff-only
      else
        git clone "$url" ${runtimeDir}
      fi

      # Claude Code rewrites this file as it runs, so only put it back when the
      # last reset took it away.
      if [ ! -f "$HOME/.claude.json" ]; then
        install -m0600 ${runtimeDir}/claude.json "$HOME/.claude.json"
      fi

      args=(run --profile "$profile" ''${opts[@]+"''${opts[@]}"})
      if [ "$#" -gt 0 ]; then
        args+=(--prompt "$*")
      fi
      python3 ${runtimeDir}/autonomous_agent.py "''${args[@]}" 2>&1 \
        | tee -a ${workDir}/state/agent.log
    '';
  };
in
{
  # --------------------------- VM hardware ---------------------------------- #
  microvm = {
    hypervisor = "qemu";
    # Raise this if builds inside the VM are too slow.
    vcpu = 2;
    inherit mem;

    interfaces = [
      {
        type = "tap";
        id = tapName;
        mac = "02:00:00:00:aa:01";
      }
    ];

    # The VM boots from a read-only nix store. Anything it builds goes to the
    # writable copy on top.
    writableStoreOverlay = "/nix/.rw-store";

    volumes = [
      {
        image = "${baseDir}/disk/root.img";
        mountPoint = "/";
        label = "root";
        fsType = "ext4";
        size = disk;
      }
    ];

    # Folders shared with the host. These are the only things `agent-vm-reset`
    # does not wipe.
    shares = [
      {
        source = "${baseDir}/nix-store";
        mountPoint = "/nix/.rw-store";
        tag = "nix-cache";
        proto = "virtiofs";
      }
      {
        source = "${baseDir}/state";
        mountPoint = "${workDir}/state";
        tag = "state";
        proto = "virtiofs";
      }
      {
        source = "${baseDir}/config";
        mountPoint = "${workDir}/state/config";
        tag = "config";
        proto = "virtiofs";
      }
      {
        source = "${baseDir}/secrets";
        mountPoint = "/run/agent-secrets";
        tag = "secrets";
        proto = "virtiofs";
      }
      {
        source = "${baseDir}/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tsstate";
        proto = "virtiofs";
      }
    ];
  };

  # --------------------------- VM system ------------------------------------ #
  system.stateVersion = "26.05";
  networking.hostName = vmName;
  time.timeZone = "Europe/Paris";

  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network = {
    enable = true;
    networks."10-uplink" = {
      matchConfig.MACAddress = "02:00:00:00:aa:01";
      address = [ "${vmIp}/24" ];
      routes = [ { Gateway = "10.77.0.1"; } ];
      # Public resolvers. The host passes traffic on; it is not our DNS server.
      dns = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      linkConfig.RequiredForOnline = "routable";
    };
  };
  services.resolved.enable = true;

  # Needed to talk to our own HTTPS services, such as Plane.
  security.pki.certificates = [
    (builtins.readFile ../step-ca/roots.pem)
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [ "https://cache.numtide.com" ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    trusted-users = [
      "root"
      "agent"
    ];
  };

  # The agent starts the software it tests in containers or small VMs.
  boot.enableContainers = true;
  boot.kernelModules = [ "kvm-intel" ];
  virtualisation.docker.enable = true;

  # How the VM reaches Plane: the host blocks mesh traffic, so the VM joins the
  # mesh itself. Do this once, the first time you log in:
  #   tailscale up --login-server https://mesh.gquetel.fr
  # It is remembered afterwards, including across a reset.
  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # Way back in if ssh breaks: run `microvm -c agent-vm` on the host. Root there
  # can already read the VM's disk, so this gives away nothing new.
  services.getty.autologinUser = "root";
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  users.mutableUsers = false;
  users.users.agent = {
    isNormalUser = true;
    uid = agentUid;
    home = workDir;
    createHome = true;
    extraGroups = [
      "docker"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI/nKCR/pq8yHrDdlQ3ml1jcio0Npxm5D7vJlG4QaDi gquetel@charybdis"
      # The host, for `agent-run`.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKd5Lwiv2fv6BBmJ4Pb/ttQpsuyqWQbbg2LvxKQuF1OM vapula@gquetel.fr"
    ];
  };
  # The agent runs unattended; a password prompt would hang it.
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = [
    claude-code
    launcher
  ]
  ++ (with pkgs; [
    git
    curl
    jq
    python3
    ripgrep
    tmux
    nixos-container
  ]);

  # Claude Code keeps its own state and its credentials in ~/.claude. The home
  # dir is wiped by agent-vm-reset, the shared folder is not.
  systemd.tmpfiles.rules = [
    "d ${workDir}/state/config/claude 0700 agent users -"
    "L+ ${workDir}/.claude - - - - ${workDir}/state/config/claude"
  ];

  # Loads the keys when you log in, for commands you type yourself. A script
  # gets no interactive shell, so it reads /run/agent-secrets/env itself; the
  # launcher above does.
  environment.interactiveShellInit = ''
    if [ -r /run/agent-secrets/env ]; then
      set -a
      . /run/agent-secrets/env
      set +a
    fi
  '';
}
