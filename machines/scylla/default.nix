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
    ../../modules/systemd-resolved
    ../../modules/vscode
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
  # dynamic network configuration: https://wiki.nixos.org/wiki/Systemd/networkd
  # networking.networkmanager.enable = true;
  networking.hostName = "scylla";

  # This is a laptop, which hop from network to network, I need a dynamic config
  # found on wiki [1]
  # - [1]: https://wiki.nixos.org/wiki/Systemd/networkd#DHCP/RA
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;

    networks."10-wlan" = {
      matchConfig.Name = "wlp0s20f3";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      # make routing on this interface a dependency for network-online.target
      linkConfig.RequiredForOnline = "routable";
    };

    networks."20-wired" = {
      matchConfig.Name = "enp86s0";
      networkConfig = {
        # start a DHCP Client for IPv4 Addressing/Routing
        DHCP = "ipv4";
        # accept Router Advertisements for Stateless IPv6 Autoconfiguraton (SLAAC)
        IPv6AcceptRA = true;
      };
      # this port is not always connected and not required to be online
      linkConfig.RequiredForOnline = "routable";
    };
  };
  networking.networkmanager.enable = true;

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

  environment.systemPackages = with pkgs; [
    gnome-tweaks
  ];

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
        zoom-us
        zotero
      ]
      ++ [
        (pkgs.callPackage "${(import ../../npins).agenix}/pkgs/agenix.nix" { })
      ];
  };

  # ---------------- Custom modules ----------------

  # ---------------- Custom services  ----------------

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
