# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/vscode
    ../../modules/fish
  ];

  # ---------------- Automatically generated  ----------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.networkmanager.enable = true;
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
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "fr";
    variant = "azerty";
  };
  console.keyMap = "fr";
  services.printing.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ---------------- My config  ----------------
  networking.hostName = "scylla";
  deployment = {
    allowLocalDeployment = true;
    targetHost = null; # Disable colmena SSH deployment.
  };
  virtualisation.docker.enable = true;
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  environment.systemPackages = with pkgs; [ ];

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      black
      colmena
      drawio
      eclipses.eclipse-sdk
      element-desktop
      firefox
      gimp
      git
      git-lfs
      htop
      hugo
      nix-init
      nixfmt-rfc-style
      npins
      obsidian
      openvpn
      ripgrep
      signal-desktop
      spotify
      texliveFull
      thunderbird
      tinymist
      tree
      unstable.typst
      typstfmt
      wget
      zoom-us
      zotero
    ];
  };

  # ---------------- Custom modules ----------------

  vscode = {
    enable = true;
    user = "gquetel";
  };
  fish.enable = true;

  # ---------------- Custom services  ----------------
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
