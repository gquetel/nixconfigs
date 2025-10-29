# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/firefox
    ../../modules/fish
    ../../modules/fonts
    ../../modules/headscale-client
    # ../../modules/systemd-resolved
    ../../modules/vscode
    ../../modules/languagetool
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
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "fr";
    variant = "azerty";
  };
  console.keyMap = "fr";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ---------------- My config  ----------------
    machine.meta = {
    ipTailscale = "100.64.0.4";
  };
  # Allows to build for aarch64.
  # https://colmena.cli.rs/unstable/examples/multi-arch.html
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  deployment = {
    allowLocalDeployment = true;
    targetHost = null; # Disable colmena SSH deployment.
  };

  virtualisation.docker.enable = true;

  # ---------------- Networking  ----------------
  # From the doc is seems that systemd-networkd might not be suited for laptops with
  networking.networkmanager.enable = true;
  networking.hostName = "scylla";
  # We disablel systemd-resolved because it somehow fucks up the
  # access to cluster machines @ Télécom.

  # Procrastination websites to ban.
  networking.extraHosts = ''
    127.0.0.1 reddit.com
    127.0.0.1 www.reddit.com
    127.0.0.1 x.com
  '';

  networking.nameservers = [
    "80.67.169.12"
    "1.1.1.1"
    "9.9.9.9"

    "80.67.169.40"
    "1.0.0.1"
    "149.112.112.112"
  ];

  # ---------------- Drivers ----------------
  # GPU
  # https://wiki.nixos.org/w/index.php?title=Jellyfin&mobileaction=toggle_view_desktop#VAAPI_and_Intel_QSV
  # New drivers so iHD
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    packages =
      with pkgs;
      [
        black
        drawio
        element-desktop
        hugo
        intel-gpu-tools
        nix-init
        nixfmt-rfc-style
        obsidian
        openvpn
        signal-desktop
        spotify
        texliveFull
        thunderbird
        tinymist
        typst
        typstfmt
        vlc
        zoom-us
        zotero
      ]
      ++ [
        (pkgs.callPackage "${(import ../../npins).agenix}/pkgs/agenix.nix" { })
      ];
  };

  # ---------------- Custom modules ----------------

  # ---------------- Custom services  ----------------
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gpu-screen-recorder-gtk # Recording App

  ];
  programs.gpu-screen-recorder.enable = true; # For promptless recording on both CLI and GUI

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
