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
    ../../modules/headscale-client
    ../../modules/servers
    ../../modules/systemd-resolved
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

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABgZ5qqnOl8LXcq2m/xaaKZlEB/ORDwIwaFSXJDs2eR gquetel@hydra"
    ];
  };

  users.users.root = {
    description = "System administrator";
    home = "/root";
    group = "root";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABgZ5qqnOl8LXcq2m/xaaKZlEB/ORDwIwaFSXJDs2eR gquetel@hydra"
    ];
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
      443
    ];
    useNetworkd = true;
  };

  systemd.network = {
    enable = true;

    networks."10-wired" = {
      # Match device name.
      matchConfig.Name = "enp0s31f6";
      # TODO: Single variable holding DNS servers provided to resolved
      dns = [
        "80.67.169.12"
        "1.1.1.1"
        "80.67.169.40"

        "9.9.9.9"
        "1.0.0.1"
        "149.112.112.112"
      ];

      # static IPv4 or IPv6 addresses and their prefix length
      addresses = [
        { Address = "192.168.1.37/24"; }
        { Address = "2a01:cb00:1d3a:1100::0007/64"; }
      ];

      # Routes define where to route a packet (Gateway) given a destination range.
      routes = [
        {
          routeConfig = {
            Gateway = "192.168.1.1";
            Destination = "0.0.0.0/0";
          };
        }
      ];
      # make routing on this interface a dependency for network-online.target
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # ----------------- Drivers -----------------
  # This permit ffmpeg to transcode using hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };
  # TODO: Debug so that encoding / decoding uses GPU
  # systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";
  # environment.sessionVariables = {
  #   LIBVA_DRIVER_NAME = "iHD";
  # };

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

  services.nginx = {
    enable = true;
    logError = "/var/log/nginx/error.log error";
    recommendedProxySettings = true;
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  # ---------------- Modules ----------------
  common.useLatestKernel = false; # We use a kernel version that supports zfs
  servers.motd = {
    enable = true;
    settings = {
      uptime.prefix = "Up";
      service_status.nginx = "nginx";
      service_status.tailscale = "tailscaled";
      service_status.jellyfin = "jellyfin";
      service_status.deluged = "deluged";
      service_status.sonarr = "sonarr";
      service_status.radarr = "radarr";
      service_status.jackett = "jackett";

      filesystems.root = "/";
      filesystems.boot = "/boot";
      filesystems.mmedia = "/mmedia";
      memory.swap_pos = "none";
      last_login.gquetel = 3;
      fail_2_ban.jails = [ "sshd" ];
    };
  };
  # ---------------- age secrets ----------------

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
