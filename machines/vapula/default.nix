{
  lib,
  config,
  pkgs,
  ...
}:
let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fail2ban
    ../../modules/fish
    ../../modules/mediaserver
    ../../modules/tailscale
    ../../modules/servers
    ../../modules/mullvad
    ../../modules/hermes
    ../../modules/agent-vm
    ../../modules/wazuh-agent

    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # ---------------- Automatically generated  ----------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };
  console.keyMap = "fr";

  # ---------------- My config  ----------------
  machine.meta = {
    ipTailscale = "100.64.0.2";
  };

  # ---------------- ZFS  ----------------
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs = {
    # auto-mount dataset
    extraPools = [ "mmedia" ];
    forceImportRoot = false;
  };
  networking.hostId = "b53a3e73";

  # https://wiki.nixos.org/wiki/ZFS
  boot.kernelPackages = latestKernelPackage;

  # Bound the ZFS ARC to 12GB (we run VMs)
  boot.kernelParams = [ "zfs.zfs_arc_max=12884901888" ];

  # Aliases mapping between disk drive color & device link identifier.
  # https://resinfo-gt.pages.in2p3.fr/zfs/doc/configuration/disques.html#le-fichier-vdev-id-conf
  # Can be reloaded by updating this file & running `udevadm trigger` whenever
  # zpool membership is changed.
  environment.etc."zfs/vdev_id.conf".text = ''
    alias blue  wwn-0x5000cca0bcf66d46
    alias red wwn-0x5000cca0bcf73bc1
  '';

  # ---------------- Networking  ----------------
  networking = {
    hostName = "vapula";
    firewall.allowedTCPPorts = [
      22
      80
    ];
    # Ports 443 and 444 are only reachable from strix (SNI proxy) over IPv6.
    # All public HTTPS traffic must transit strix; direct connections to this
    # backend's TLS ports from the LAN or the internet are dropped.
    firewall.extraCommands = ''
      ip6tables -A nixos-fw -p tcp --dport 443 -s 2a01:cb00:253:ed00::3 -j nixos-fw-accept
      ip6tables -A nixos-fw -p tcp --dport 444 -s 2a01:cb00:253:ed00::3 -j nixos-fw-accept
    '';
  };

  servers.lanAddresses = [
    "192.168.1.37/24"
    "2a01:cb00:253:ed00::0007/64"
  ];

  # ----------------- Drivers -----------------
  # This permit ffmpeg to transcode using hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  environment.systemPackages = with pkgs; [
    goaccess
    intel-gpu-tools
  ];

  # ---------------- Deployment info ----------------
  deployment.targetHost = "vapula";
  deployment.targetUser = "root";

  # ---------------- Services ----------------

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  systemd.services.nginx = {
    after = [ "tailscale-online.service" ];
    requires = [ "tailscale-online.service" ];
  };

  # ---------------- Modules ----------------
  # The [Peer] section of a WireGuard config
  mullvad = {
    enable = true;
    publicKey = "HUj/J8Rxx7QVGh3kJsFgPZoqtm2BQIX03vKJSIyTOSo=";
    endpoint = "149.102.240.66:51820";
  };

  # Tailscale node in the Mullvad namespace, used as exit node to have both access to internal services and Mullvad.
  systemd.services.tailscaled-mullvad = lib.mkMerge [
    config.mullvad.confine
    {
      description = "Tailscale exit node through Mullvad";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.unstable.tailscale}/bin/tailscaled"
          "--tun=userspace-networking"
          "--statedir=/var/lib/tailscale-mullvad"
          "--socket=/run/tailscale-mullvad/tailscaled.sock"
          "--port=0"
        ];
        StateDirectory = "tailscale-mullvad";
        RuntimeDirectory = "tailscale-mullvad";
        Restart = "on-failure";
      };
    }
  ];

  hermes.enable = true;
  hermes.plane.enable = true;

  # VM for the agents. Its credentials arrive as two env files: the Plane
  # token still rides on the hermes secret, the agent's own keys have theirs.
  agent-vm = {
    enable = true;
    environmentFiles = [
      config.age.secrets.hermes-plane-token.path
      config.age.secrets.agent-secrets.path
    ];
  };

  programs.rust-motd.settings = {
    service_status = {
      tailscale = "tailscaled";
      jellyfin = "jellyfin";
      seerr = "seerr";
      deluged = "deluged";
      sonarr = "sonarr";
      radarr = "radarr";
      jackett = "jackett";
    };
    filesystems.mmedia = "/mmedia";
  };

  # ---------------- age secrets ----------------

  # The agent VM's own keys: CLAUDE_CODE_OAUTH_TOKEN, made with
  # `claude setup-token` and re-keyed by hand when it expires, and
  # AGENT_RUNTIME_TOKEN, a fine-grained PAT with Contents: read on
  # gquetel/agent-runtime.
  age.secrets.agent-secrets.file = ../../secrets/agent-secrets.env.age;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
