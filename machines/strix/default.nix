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
    ../../modules/common

    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  console.keyMap = "fr";
  networking.useNetworkd = true;
  networking.hostName = "strix";

  # Colmena deployment info
  deployment.targetHost = "gquetel.fr";
  deployment.targetUser = "root";

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

  # TODO: Review the following config, might be useless / wrong.
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      Address = "192.168.1.33/24";
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

  # Changed passwords will be reset according to the users.users configuration.
  users.mutableUsers = false;

  # Enable automatic login for the user.
  services.getty.autologinUser = "gquetel";

  users.users.gquetel = {
    hashedPasswordFile = config.age.secrets.gquetel-strix.path;
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

  services.openssh.enable = true;
  services.openssh.settings.LogLevel = "VERBOSE"; # Required by fail2ban, should be set by default, but just in case.

  # ----------------- age secrets -----------------
  # https://github.com/ryantm/agenix?tab=readme-ov-file#agesecretsnamemode
  age.secrets.gitlab-runner-env.file = ../../secrets/gitlab-runner.env.age;
  age.secrets.gquetel-strix.file = ../../secrets/gquetel-strix.age;
  age.secrets.thesis-artefacts = {
    file = ../../secrets/thesis-artefacts.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };

  # ----------------- Gitlab runner -----------------
  # From: https://wiki.nixos.org/wiki/Gitlab_runner

  # First create a runner instance for a project, the value for both the
  # CI_SERVER_URL & CI_SERVER_TOKEN will be given. My jobs do not have any tags so i must
  # enable the option "Run untagged jobs" on the runner options.
  # Then, create a .env file with given values.

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
        # `CI_SERVER_TOKEN`
        authenticationTokenConfigFile = config.age.secrets.gitlab-runner-env.path;
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
          ${pkgs.nix}/bin/nix-channel --add https://nixos.org/channels/nixos-25.05 nixpkgs
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

  services.nginx = {
    enable = true;
    logError = "/var/log/nginx/error.log error";
  };
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
        auth_basic_user_file ${config.age.secrets.thesis-artefacts.path} ;

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

    locations."/robots.txt" = {
      return = "200 'User-agent: *\nDisallow: /\n'";
      extraConfig = ''
        add_header Content-Type text/plain;
      '';
    };

  };

  # Reject all other invalid sub-subdomains.
  # TODO: Is there a better way to do this ?
  # 80 is sent to 404 and https sent a SSL error.
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

  # ----------------- Mediaserver -----------------
  users.groups.mediaserver = {
    name = "mediaserver";
  };

  users.users.mediaserver = {
    name = "mediaserver";
    # uid = 1001;
    isNormalUser = true;
    home = "/home/mediaserver";
    group = "mediaserver";
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

  # This permit ffmpeg to transcode using hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  services.jackett = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };
  systemd.tmpfiles.rules = [
    "d /run/other-keys/ 755 mediaserver mediaserver -"
  ];

  # Deluge génère automatiquement un mdp au boot dans /run/other-keys/deluge.
  # ATM, Il faut manuellement modifier le profil dans delugeweb.
  # TODO: Trouver comment ajouter de la persistance avec ce fichier

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
      max_active_seeding = 50;
      max_active_downloading = 10;
      max_active_limit = 60;
    };
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
    goaccess
    intel-gpu-tools
  ];

  # ---------------- Custom modules ----------------
  fish.enable = true;
  common.enable = true;
  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
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
