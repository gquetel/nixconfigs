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
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCwAqvvbyI8a6qH3yVxh9Dz9QPUDwW235yGtBM9oUrkSLpnYVrVQXPCTuMf66xBOkvjZfMixkcxfYd/LmpcYI/EU6c2TJ+8s4PdjB/Poqc6sMDOf99rEIfAs6P5g1+TJc1Yh2uS7e+u7Lbx9wH0YBjirSlzhlj8ttJenzu4U3m6NcgAiT4QNke1K3oTYlLc+sDx4MQyZ5UG+YEa7uUan65Kw3LOgQghCFvkTXKgG9XPlzVUMcRL0m8wpraP4N4lHWvq+uD7TGH6gp/TA6r7ufu0/lKZZxkH5hbBKeAWhI/VmdCuS//UFqomVt+qi3Fflcg8Tw8QQgmzfCzxRGZ9NmvoTRmP9fZq7OmgPyBkL8Lm3KTH2WMpMHpDZK7NwgVJIPK3xfj2TCs1ldT9OkwWQaIdfwPxDqvdv2z52B31dAMj1bJCpR1Cj2+/Wx7xTh6v/oMTXhMx9DyZDwVzE0ejfw+tmEJHfBjQUJBxMfmIX5c0R2FkdtDpgbKD7kWNY11IcAk= gquetel@scylla"
    ];
    packages = with pkgs; [
      tree
    ];
  };

  users.users.root = {
    description = "System administrator";
    home = "/root";
    group = "root";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCwAqvvbyI8a6qH3yVxh9Dz9QPUDwW235yGtBM9oUrkSLpnYVrVQXPCTuMf66xBOkvjZfMixkcxfYd/LmpcYI/EU6c2TJ+8s4PdjB/Poqc6sMDOf99rEIfAs6P5g1+TJc1Yh2uS7e+u7Lbx9wH0YBjirSlzhlj8ttJenzu4U3m6NcgAiT4QNke1K3oTYlLc+sDx4MQyZ5UG+YEa7uUan65Kw3LOgQghCFvkTXKgG9XPlzVUMcRL0m8wpraP4N4lHWvq+uD7TGH6gp/TA6r7ufu0/lKZZxkH5hbBKeAWhI/VmdCuS//UFqomVt+qi3Fflcg8Tw8QQgmzfCzxRGZ9NmvoTRmP9fZq7OmgPyBkL8Lm3KTH2WMpMHpDZK7NwgVJIPK3xfj2TCs1ldT9OkwWQaIdfwPxDqvdv2z52B31dAMj1bJCpR1Cj2+/Wx7xTh6v/oMTXhMx9DyZDwVzE0ejfw+tmEJHfBjQUJBxMfmIX5c0R2FkdtDpgbKD7kWNY11IcAk= gquetel@scylla"
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
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
    };
  };

  services.nginx.virtualHosts."gquetel.fr" = {
    addSSL = true;
    enableACME = true;
    root = "/var/www/html/gquetel.fr";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  services.openssh.enable = true;
  services.openssh.settings.LogLevel = "VERBOSE"; # Required by fail2ban, should be set by default, but just in case.

  # ----------------- Movies -----------------
  services.jellyfin = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
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
    "fail2ban/filter.d/jellyfin.conf".text = 
    ''[Definition]
      failregex = ^.*Authentication request for .* has been denied \(IP: "?<ADDR>"?\)\.'';
    
    "fail2ban/jail.d/jellyfin.local".text = 
    ''[jellyfin]

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
  

  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];


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
