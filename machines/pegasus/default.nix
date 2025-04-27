{ lib, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware.nix
    ../../modules/fish
    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  disko = import ./disko.nix;

  nixpkgs.config.permittedInsecurePackages = [
    "dotnet-sdk-6.0.428"
    "aspnetcore-runtime-6.0.36"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";

  networking.useNetworkd = true;
  networking.hostName = "pegasus";
  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];

  networking.nameservers = [
    "80.67.169.12"
    "80.67.169.40"
    "8.8.8.8"
    "8.8.4.4"
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

  users.groups.mediaserver = {
    name = "mediaserver";
  };

  users.users.mediaserver = {
    name = "mediaserver";
    uid = 1001;
    isNormalUser = true;
    home = "/home/mediaserver";
    group = "mediaserver";
  };

  # ----------------- Gitlab runner -----------------
  # From: https://nixos.wiki/wiki/Gitlab_runner

  boot.kernel.sysctl."net.ipv4.ip_forward" = true; # Required for cloning
  virtualisation.docker.enable = true;

  services.gitlab-runner = {
    enable = true;
    services = {
      # runner for building in docker via host's nix-daemon
      # nix store will be readable in runner, might be insecure
      nix = with lib; {
        # File should contain at least these two variables:
        # `CI_SERVER_URL`
        # `REGISTRATION_TOKEN`

        # TODO: Automatically deploy with agenix
        registrationConfigFile = toString ~/.config/gitlab-runner/ci.env;
        dockerImage = "alpine";
        dockerVolumes = [
          "/nix/store:/nix/store:ro"
          "/var/www/pdfs:/var/www/pdfs"
          "/nix/var/nix/db:/nix/var/nix/db:ro"
          "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket:ro"
        ];
        dockerDisableCache = true;
        preBuildScript = pkgs.writeScript "setup-container" ''
          mkdir -p -m 0755 /nix/var/log/nix/drvs
          mkdir -p -m 0755 /nix/var/nix/gcroots
          mkdir -p -m 0755 /nix/var/nix/profiles
          mkdir -p -m 0755 /nix/var/nix/temproots
          mkdir -p -m 0755 /nix/var/nix/userpool
          mkdir -p -m 1777 /nix/var/nix/gcroots/per-user
          mkdir -p -m 1777 /nix/var/nix/profiles/per-user
          mkdir -p -m 0755 /nix/var/nix/profiles/per-user/root
          mkdir -p -m 0700 "$HOME/.nix-defexpr"
          . ${pkgs.nix}/etc/profile.d/nix-daemon.sh
          ${pkgs.nix}/bin/nix-channel --add https://nixos.org/channels/nixos-24.11 nixpkgs 
          ${pkgs.nix}/bin/nix-channel --update nixpkgs
          ${pkgs.nix}/bin/nix-env -i ${
            concatStringsSep " " (
              with pkgs;
              [
                nix
                cacert
                git
                openssh
              ]
            )
          }
        '';
        environmentVariables = {
          ENV = "/etc/profile";
          USER = "root";
          NIX_REMOTE = "daemon";
          PATH = "/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/sbin:/usr/bin:/usr/sbin";
          NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
        };
        tagList = [ "nix" ];
      };
    };
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

  services.nginx.virtualHosts."thesis-artefacts.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/www/pdfs";
    locations."/" = {
      extraConfig = ''
        auth_basic "Documents de thèse de Grégor"; 
        auth_basic_user_file /run/other-keys/nginx-protected.htpasswd ;

        types {
          application/pdf pdf;
        }
        autoindex on;
      '';
    };
  };

  services.nginx.virtualHosts."gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/www/html/gquetel.fr";
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
    enable = false;
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

  # ----------------- Movies -----------------
  services.flaresolverr = {
    enable = true;
    package = pkgs.callPackage ../../packages/flaresolverr { };
  };

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
    package = pkgs.unstable.jackett.overrideAttrs (
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
    broot
    htop
    goaccess
    git
    tree
    wget
  ];
  # ---------------- Custom modules ----------------
  fish.enable = true;

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
