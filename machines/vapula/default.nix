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
    ../../modules/prometheus-exporters
    ../../modules/wireguard-client

    # ../../modules/systemd-resolved
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

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "wheel"
      "nginx"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI/nKCR/pq8yHrDdlQ3ml1jcio0Npxm5D7vJlG4QaDi gquetel@charybdis"
    ];
  };

  users.users.root = {
    description = "System administrator";
    home = "/root";
    group = "root";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI/nKCR/pq8yHrDdlQ3ml1jcio0Npxm5D7vJlG4QaDi gquetel@charybdis"
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
      444
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
        { Address = "2a01:cb00:253:ed00::0007/64"; }
      ];

      # Routes define where to route a packet (Gateway) given a destination range.
      routes = [
        {
          Gateway = "192.168.1.1";
          Destination = "0.0.0.0/0";
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
    # Set headers for the proxied server such as X-Forwarded-For.
    # See, code for modified headers:
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/web-servers/nginx/default.nix
    recommendedProxySettings = true;

    appendHttpConfig = ''
      log_format vcombined '$host:$server_port '
              '$remote_addr - $remote_user [$time_local] '
              '"$request" $status $body_bytes_sent '
              '"$http_referer" "$http_user_agent"';

      access_log /var/log/nginx/access.log vcombined;

      #  Defines trusted addresses that are known to send correct replacement addresses
      set_real_ip_from 2a01:cb00:253:ed00::/64;

      # Defines the request header field whose value will be used to replace the client address.
      real_ip_header proxy_protocol;
    '';
  };
  systemd.services.nginx = {
    after = [ "tailscale-online.service" ];
    requires = [ "tailscale-online.service" ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  # ---------------- Modules ----------------
  wg0.enable = true;

  common.useLatestKernel = false; # We use a kernel version that supports zfs
  servers.motd = {
    enable = true;
    settings = {
      uptime.prefix = "Up";
      service_status.nginx = "nginx";
      service_status.tailscale = "tailscaled";
      service_status.jellyfin = "jellyfin";
      service_status.jellyseerr = "jellyseerr";
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

  prometheus_exporter = {
    node = {
      enable = true;
      addr = config.machine.meta.ipTailscale;
    };
    nginx = {
      enable = true;
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
