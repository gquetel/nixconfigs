{
  config,
  nodes,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fail2ban
    ../../modules/fish
    ../../modules/headscale-client
    ../../modules/headscale-server
    ../../modules/step-ca
    ../../modules/servers
    ../../modules/grafana
    ../../modules/prometheus
    ../../modules/prometheus-ne
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
    ipTailscale = "100.64.0.5";
  };

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "nginx"
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
  # FIXME: When booting the machine, nginx will check as ca.mesh.gq for certificates, nginx is started before
  # tailscale / headscale, hence it does not find ca.mesh.gq. There might be a better workaround.
  # networking.hosts = {
  #   "127.0.0.1" = [ "ca.mesh.gq" ];
  # };

  # ---------------- Networking  ----------------
  # systemd-networkd should be prefered over "scripted networking". Refs:
  # - https://wiki.archlinux.org/title/Systemd-networkd
  # - https://wiki.nixos.org/wiki/Systemd/networkd
  # - https://man7.org/linux/man-pages/man5/systemd.netdev.5.html For networks configs.

  networking.useNetworkd = true;
  systemd.network = {
    enable = true;

    networks."10-wired" = {
      # Match device name.
      matchConfig.Name = "enp0s31f6";
      # static IPv4 or IPv6 addresses and their prefix length
      addresses = [
        { Address = "192.168.1.28/24"; }
        { Address = "2a01:cb00:253:ed00::0005/64"; }
      ];

      # TODO: Single variable holding DNS servers provided to resolved
      dns = [
        "80.67.169.12"
        "1.1.1.1"
        "80.67.169.40"

        "9.9.9.9"
        "1.0.0.1"
        "149.112.112.112"
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

      # Disable SLAAC. It seems that it mess with the identification of the
      # machine by the Orange router: the machine seems to be identified by the
      # temporary address, then the firewall does not allow traffic directed at the
      # IPV6 address given above...
      networkConfig = {
        IPv6AcceptRA = true; # disable SLAAC (no RAs)
      };
    };
  };

  networking = {
    hostName = "garmr";
    firewall.allowedTCPPorts = [
      22
      80
      443
      444 # TODO: MODULE
    ];
  };

  # ---------------- Deployment info ----------------
  deployment.targetHost = "garmr";
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

  # ---------------- Modules ----------------
  servers.motd = {
    enable = true;
    settings = {
      uptime.prefix = "Up";
      service_status.nginx = "nginx";
      service_status.headscale = "headscale";
      service_status.tailscale = "tailscaled";
      service_status.prometheus = "prometheus";
      service_status.prometheus_node_exporter = "prometheus-node-exporter";
      service_status.step-ca = "step-ca";
      filesystems.root = "/";
      last_login.gquetel = 3;
      filesystems.boot = "/boot";
      memory.swap_pos = "none";
      fail_2_ban.jails = [ "sshd" ];
    };
  };

  grafana.enable = true;
  prometheus.enable = true;

  prometheus_ne = {
    enable = true;
    addr = config.machine.meta.ipTailscale;
  };

  # ---------------- age secrets ----------------
  age.secrets.step-ca-pwd.file = ../../secrets/step-ca.pwd.age;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
