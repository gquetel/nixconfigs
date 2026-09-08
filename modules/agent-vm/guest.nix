{
  lib,
  pkgs,
  vmName,
  tapName,
  baseDir,
  agentUid,
  mem,
  disk,
  ...
}:
# The system inside the VM.
#
# An ordinary machine with nix, docker, tmux and ssh. It does not know or care
# which agent you run. Start one by hand:
#
#   ssh agent@<vm>               (or `ssh agent@10.77.0.2` from the host)
#   tmux new -s night
#   nix run github:gquetel/agent-runtime -- ...
let
  workDir = "/work";
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
        source = "${baseDir}/hermes";
        mountPoint = "${workDir}/.hermes";
        tag = "hermes";
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
      address = [ "10.77.0.2/24" ];
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
    ];
  };
  # The agent runs unattended; a password prompt would hang it.
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    curl
    jq
    ripgrep
    tmux
    nixos-container
  ];

  # Keeps Hermes' settings and API keys on the shared folder, so a reset does
  # not lose them.
  environment.variables.HERMES_HOME = "${workDir}/.hermes";

  # Loads the keys when you log in. Scripts started by ssh or tmux skip this,
  # so they have to read /run/agent-secrets/env themselves.
  environment.interactiveShellInit = ''
    if [ -r /run/agent-secrets/env ]; then
      set -a
      . /run/agent-secrets/env
      set +a
    fi
  '';
}
