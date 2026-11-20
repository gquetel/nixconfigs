{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/common
    ../../modules/fail2ban
    ../../modules/fish
    ../../modules/servers
    ../../modules/garage
    ../../modules/tailscale
    ../../modules/wazuh-agent
    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "fr";

  # ---------------- My config  ----------------
  machine.meta = {
    ipTailscale = "100.64.0.8";
  };

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
  deployment.targetHost = "fafnir";
  deployment.targetUser = "root";

  # ---------------- Services ----------------
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # ---------------- Modules ----------------
  garage.enable = true;
  programs.rust-motd.settings.service_status = {
    garage = "garage";
    tailscale = "tailscaled";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?
}
