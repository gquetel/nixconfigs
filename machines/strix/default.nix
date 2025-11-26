{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware.nix
    ../../modules/fish
    ../../modules/fonts
    ../../modules/common
    ../../modules/headscale-client
    ../../modules/fail2ban
    # ../../modules/systemd-resolved
    ../../modules/gitlab-runner
    ../../modules/outline
    ../../modules/servers
    ../../modules/prometheus-ne

    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  console.keyMap = "fr";

  # ---------------- My config  ----------------
  machine.meta = {
    ipTailscale = "100.64.0.3";
  };
  # Changed passwords will be reset according to the users.users configuration.
  users.mutableUsers = false;

  users.users.gquetel = {
    hashedPasswordFile = config.age.secrets.gquetel-strix.path;
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "nginx"
    ];
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

  # ---------------- Networking  ----------------
  networking = {
    hostName = "strix";
    firewall.allowedTCPPorts = [
      22
      80
      443
      444
    ];
  };

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
        { Address = "192.168.1.33/24"; }
        { Address = "2a01:cb00:253:ed00::0003/64"; }
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

  # Colmena deployment info
  deployment.targetHost = "strix";

  # ----------------- age secrets -----------------
  # https://github.com/ryantm/agenix?tab=readme-ov-file#agesecretsnamemode
  age.secrets.gquetel-strix.file = ../../secrets/gquetel-strix.age;
  age.secrets.thesis-artefacts = {
    file = ../../secrets/thesis-artefacts.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };

  # ----------------- Drivers -----------------

  environment.systemPackages = with pkgs; [
    goaccess
  ];

  # ----------------- Services -----------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  # SNI Proxy Ressources:
  # - https://blog.le-vert.net/?p=224
  # -  https://nginx.org/en/docs/http/ngx_http_realip_module.html
  # - https://github.com/JulienMalka/snowfield/blob/f3e41b53c459fc4bda0d0773851dc0753e6e27ae/profiles/behind-sniproxy.nix#L10

  # ------------ Nginx ------------
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

    streamConfig = ''
      map $ssl_preread_server_name $targetBackend {
         movies.gquetel.fr   [2a01:cb00:253:ed00::7]:444;
         dmd.gquetel.fr   [2a01:cb00:253:ed00::7]:444;
         mesh.gquetel.fr   [2a01:cb00:253:ed00::5]:444;
         
         default [::1]:444;
      }

      log_format proxy '$remote_addr -> $targetBackend';
      access_log /var/log/nginx/proxy.log proxy;

      server {
          listen 192.168.1.33:443;
          proxy_protocol on;
          proxy_pass $targetBackend;
          ssl_preread on;
      }
    '';
  };

  # This allows to route HTTP ACME requests to vapula.
  services.nginx.virtualHosts."dmd.gquetel.fr" = {
    listen = [{ addr = "0.0.0.0"; port = 80; }];
    locations."/".proxyPass = "http://[2a01:cb00:253:ed00::7]";
  };

  # This allows to route HTTP ACME requests to garmr.
  services.nginx.virtualHosts."mesh.gquetel.fr" = {
    listen = [{ addr = "0.0.0.0"; port = 80; }];
    locations."/".proxyPass = "http://[2a01:cb00:253:ed00::5]";
  };
  

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  services.nginx.virtualHosts."gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    root = "/var/www/html/gquetel.fr";
  };

  # VHost on which pdf artefacts are hosted.
  services.nginx.virtualHosts."thesis-artefacts.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    root = "/var/www/pdfs";
    locations."/" = {
      extraConfig = ''
        auth_basic "Documents de thèse de Grégor";
        auth_basic_user_file ${config.age.secrets.thesis-artefacts.path} ;

        types {
          application/pdf pdf;
        }
        autoindex on;
      '';
    };
  };

  # ---------------- Modules ----------------
  servers.motd = {
    enable = true;
    settings = {
      uptime.prefix = "Up";

      service_status.nginx = "nginx";
      service_status.gitlab-runner = "gitlab-runner";
      service_status.outline = "outline";
      service_status.prometheus_node_exporter = "prometheus-node-exporter";
      
      filesystems.root = "/";
      last_login.gquetel = 3;
      filesystems.boot = "/boot";
      memory.swap_pos = "none";
      fail_2_ban.jails = [ "sshd" ];
    };
  };

  prometheus_ne = {
    enable = true;
    addr = config.machine.meta.ipTailscale;
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
