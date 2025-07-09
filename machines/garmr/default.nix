{
  config,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/headscale-server
    ../../modules/headscale-client
    ../../modules/common
    ../../modules/fish
    ../../modules/fail2ban
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
  networking.hostName = "garmr";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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

  # ---------------- Networking  ----------------
  networking.networkmanager.enable = true;
  networking = {
    # Open ports in the firewall.
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];

    interfaces.enp0s31f6 = {
      ipv6.addresses = [
        {
          # IPv6 prefix given by my FAI + my custom suffix
          address = "2a01:cb00:02c4:3a00::0005";
          prefixLength = 64;
        }
      ];

      ipv4.addresses = [
        {
          # Correspond to IP address statically set in router config for this machine.
          address = "192.168.1.28";
          prefixLength = 24;
        }
      ];
    };

    # Default ipv6 gateway: my router
    defaultGateway6 = {
      address = "2a01:cb00:2c4:3a00::1";
      interface = "enp0s31f6";
    };
    
    # Default ipv4 gateway: my router
    defaultGateway = {
      address = "192.168.1.1";
      interface = "enp0s31f6";
    };

    nameservers = [
      "8.8.8.8"
      "8.8.4.4"
    ];
  };

  # ---------------- Deployment info ----------------
  deployment.targetHost = "garmr";
  deployment.targetUser = "root";

  # ---------------- Services ----------------
  services.openssh.enable = true;
  # ---------------- Modules ----------------

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
