{ lib, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware.nix
  ];

  disko = import ./disko.nix;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  time.timeZone = "Europe/Paris";

  networking.useNetworkd = true;
  networking.hostName = "pegasus";
  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];

  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      Address = "192.168.1.30/24";
    };
    routes = [
      {
        routeConfig = {
          Gateway = "192.168.1.1";
          Destination = "0.0.0.0/0";
        };
      }
    ];
    linkConfig.RequiredForOnline = "routable";
  };

  deployment.targetHost = "gquetel.fr";

  users.users.gquetel = {
    hashedPassword = "$y$j9T$/9PMk6pMAgVtX5KMZL96C0$0pgIQnSSBe3Yn7FDVsQIh.6FZVj1edXBnKVKSfWYeJ";
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
    ];
  };

  users.users.root = {
    description = "System administrator";
    home = "/root";
    group = "root";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla"
    ];
  };

  users.groups.mediaserver = {
    name = "mediaserver";
  };

  users.users.mediaserver = {
    name = "mediaserver";
    uid = 1001;
    isNormalUser = true;
    home = "/home/mediaserver";
    # group = users.groups.mediaserver.name; # Why can't I reference users ?
    group = "mediaserver";
  };

  # ----------------- Nginx -----------------

  services.nginx.enable = true;
  services.nginx.virtualHosts."movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
    };
  };

  services.nginx.virtualHosts."deluge.movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8112";
    };
  };

  services.nginx.virtualHosts."veste.movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9117";
    };
  };

  services.nginx.virtualHosts."sonarr.movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8989";
    };
  };

  services.nginx.virtualHosts."radarr.movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:7878";
    };
  };

  services.nginx.virtualHosts."status.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
    };
  };

  services.nginx.virtualHosts."gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/www/html/gquetel.fr";
  };

  services.nginx.virtualHosts."recettes.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
    };
  };

  # Reject all other invalid sub-subdomains.
  # TODO: Is there a better way to do this ? 80 is sent to 404 and https is sent a SSL error.
  services.nginx.virtualHosts."_" = {
    rejectSSL = true;
    locations."/" = {
      return = "404";
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  services.openssh.enable = true;
  services.openssh.settings.LogLevel = "VERBOSE"; # Required by fail2ban, should be set by default, but just in case.

  # ----------------- DNSCRYPT ---------------
  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      require_dnssec = true;
      server_names = [
        "fdnipv6"
        "fdn"
        "dnscry.pt-paris-ipv4"
        "dnscry.pt-paris-ipv6"
      ];
    };
  };

  # -----------------  Recettes -----------------
  services.mealie.enable = true;

  # ----------------- Movies -----------------
  # TODO, setup flaresolverr (check for working release, current on crashes like dis: https://github.com/FlareSolverr/FlareSolverr/issues/1119)
  services.flaresolverr.enable = false; # Is broken RN

  services.sonarr = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.radarr = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.jellyfin = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.jackett = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
    package = pkgs.jackett.overrideAttrs (
      _: _: {
        postInstall = ''
          cp ${./ygg-api.yml} $out/lib/jackett/Definitions/ygg-api.yml
        '';
      }
    );
  };

  systemd.tmpfiles.rules = [
    "d /run/other-keys/ 755 mediaserver mediaserver -"
  ];

  # Deluge génère automatiquement un mdp au boot dans /run/other-keys/deluge.
  # ATM, Il faut mettre à jour manuellement le profil de la connection dans delugeweb.
  # TODO: Trouver comment ajouter de la persistance avec ce fichier (sorte de mécanisme de secrets)
  # Je crois qu'un process veut append dedans dans tous les cas, mais on peut peut-être fournir un profil par défaut.
  services.deluge = {
    enable = true;
    authFile = "/run/other-keys/deluge";
    user = "mediaserver";
    group = "mediaserver";
    declarative = true;
    openFirewall = false;
    web.enable = true;
    config = {
      download_location = "/portemer/deluge/";
      enabled_plugins = [ "Label" ];
      allow_remote = true;
    };
  };
  # ----------------- Uptime Kuma -----------------
  services.uptime-kuma = {
    enable = false;
  };

  # ----------------- Fail2ban -----------------
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "24h";
    bantime-increment.multipliers = "1 2 4 8 16 32 64";
  };

  # ----------------- /etc -----------------

  environment.etc = {
    "fail2ban/filter.d/jellyfin.conf".text = ''
      [Definition]
            failregex = ^.*Authentication request for .* has been denied \(IP: "?<ADDR>"?\)\.'';

    "fail2ban/jail.d/jellyfin.local".text = ''
      [jellyfin]
            backend = auto
            enabled = true
            port = 80,443
            protocol = tcp
            filter = jellyfin
            maxretry = 5
            bantime = 36000
            findtime = 3600
            logpath = /var/lib/jellyfin/log/log_*'';
  };

  environment.systemPackages = with pkgs; [
    wget
    htop
    goaccess
    git
  ];

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile ./interactive_init.fish;
  };

  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  # NE PAS TOUCHER LE TRUC EN BAS

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
