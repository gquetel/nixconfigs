{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/common
    ../../modules/fail2ban
    ../../modules/fish
    ../../modules/servers
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "fr";

  # ---------------- Networking ----------------
  networking.hostName = "fafnir";
  # Remote VM: IPv4 by DHCP behind NAT, public IPv6 by RA.
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "ens18";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    # Fixed interface ID so the public IPv6 address stays stable.
    ipv6AcceptRAConfig.Token = "static:::b5e6:878c:f1c3:8efe";
    linkConfig.RequiredForOnline = "routable";
  };

  # ---------------- Deployment info ----------------
  deployment.targetHost = "2a01:4f9:3090:2b8c:b5e6:878c:f1c3:8efe";
  deployment.targetUser = "root";

  # ---------------- Services ----------------
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?
}
