{
  config,
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
    ../../modules/systemd-resolved
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
        { Address = "2a01:cb00:02c4:3a00::0005/64"; }
      ];

      # Routes define where to route a packet (Gateway) given a destination range.
      routes = [
        {
          routeConfig = {
            Gateway = "192.168.1.1";
            Destination = "0.0.0.0/0";
          };
        }
      ];
      # make routing on this interface a dependency for network-online.target
      linkConfig.RequiredForOnline = "routable";
    };
  };

  networking = {
    hostName = "garmr";
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  # ---------------- Deployment info ----------------
  deployment.targetHost = "garmr";
  deployment.targetUser = "root";

  # ---------------- Services ----------------
  services.openssh.enable = true;

  # ---------------- Modules ----------------

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
