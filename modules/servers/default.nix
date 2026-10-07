{ config, lib, ... }:
let
  adminKeys = builtins.attrValues (import ../../keys.nix);
in
{
  imports = [ ../prometheus-exporters ];

  options.servers.lanAddresses = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    example = [
      "192.168.1.28/24"
      "2a01:cb00:253:ed00::5/64"
    ];
    description = "Static addresses, with prefix length, of the wired LAN interface.";
  };

  config = {
    users.users.gquetel = {
      isNormalUser = true;
      description = "gquetel";
      extraGroups = [
        "nginx"
        "wheel"
      ];
      openssh.authorizedKeys.keys = adminKeys;
    };
    users.users.root.openssh.authorizedKeys.keys = adminKeys;

    # ---------------- Networking ----------------
    # systemd-networkd should be prefered over "scripted networking". Refs:
    # - https://wiki.archlinux.org/title/Systemd-networkd
    # - https://wiki.nixos.org/wiki/Systemd/networkd
    # - https://man7.org/linux/man-pages/man5/systemd.netdev.5.html For networks configs.
    networking.useNetworkd = true;
    systemd.network.networks."10-wired" = {
      matchConfig.Name = "enp0s31f6";
      addresses = map (a: { Address = a; }) config.servers.lanAddresses;
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
    };

    # ---------------- Nginx ----------------
    services.nginx = {
      enable = true;
      logError = "/var/log/nginx/error.log error";
      # Set headers for the proxied server such as X-Forwarded-For.
      # See, code for modified headers:
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/web-servers/nginx/default.nix
      recommendedProxySettings = true;

      # The fail2ban nginx-404-scan filter reads the vcombined format.
      appendHttpConfig = ''
        log_format vcombined '$host:$server_port '
                '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent '
                '"$http_referer" "$http_user_agent"';

        access_log /var/log/nginx/access.log vcombined;

        # Defines trusted addresses that are known to send correct replacement
        # addresses: strix, the SNI proxy.
        set_real_ip_from 2a01:cb00:253:ed00::3;

        # Defines the request header field whose value will be used to replace the client address.
        real_ip_header proxy_protocol;
      '';
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = "gregor.quetel@gquetel.fr";
    };

    prometheus_exporter = {
      node = {
        enable = true;
        addr = config.machine.meta.ipTailscale;
      };
      nginx.enable = true;
    };

    # ---------------- motd ----------------
    # Hosts add their sections, e.g. `programs.rust-motd.settings.service_status`.
    # https://github.com/rust-motd/rust-motd
    programs.rust-motd = {
      enable = true;
      order = [
        "filesystems"
        "memory"
        "last_login"
        "uptime"
        "service_status"
        "fail_2_ban"
        "global"
      ];
      settings = {
        uptime.prefix = "Up";
        service_status.nginx = "nginx";
        filesystems.root = "/";
        filesystems.boot = "/boot";
        last_login.gquetel = 3;
        memory.swap_pos = "none";
        fail_2_ban.jails = [
          "sshd"
          "nginx-404-scan"
        ];
      };
    };
  };
}
