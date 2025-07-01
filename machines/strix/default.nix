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
    ../../modules/headscale-client
    ../../modules/fail2ban
    ../../modules/gitlab-runner
    ../../modules/mediaserver

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

  # ----------------- Services -----------------
  services.openssh.enable = true;

  #      ------------ Nginx ------------
  services.nginx = {
    enable = true;
    logError = "/var/log/nginx/error.log error";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
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

  # VHost on which pdf artefacts are hosted.
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

  # Reject all other invalid sub-subdomains.
  # TODO: Is there a better way to do this ?
  # 80 is sent to 404 and https sent a SSL error.
  services.nginx.virtualHosts."_" = {
    rejectSSL = true;
    locations."/" = {
      return = "404";
    };
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
