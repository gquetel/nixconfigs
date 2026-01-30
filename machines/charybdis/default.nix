{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fish
    ../../modules/firefox
    ../../modules/fonts
    ../../modules/tailscale
    # ../../modules/languagetool
    ../../modules/home-manager
    ../../modules/emacs
    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # ---------------- Automatically generated  ----------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Brussels";
  i18n.defaultLocale = "en_GB.UTF-8";

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

  # ---------------- Display ----------------
  # Single GPU setup: RTX 3060 Ti (no iGPU, AMD Ryzen CPU)
  # lspci -d ::03xx:
  # 0a:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3060 Ti Lite Hash Rate] (rev a1)

  hardware.graphics = {
    enable = true;
  };

  hardware.nvidia = {
    open = true; # Recommended for Turing+
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
  };

  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    xkb = {
      layout = "fr";
      variant = "azerty";
    };

    videoDrivers = [ "nvidia" ];
  };

  # ---------------- My config  ----------------
  machine.meta = {
    # TODO: Update
    ipTailscale = "100.64.0.9";
  };

  deployment = {
    allowLocalDeployment = true;
    targetHost = null; # Disable SSH colmena deployment.
  };

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "wheel"
      "docker" # Run docker without sudo.
    ];

    packages = with pkgs; [
      steam-run
    ];

  };

  # ---------------- Networking  ----------------
  networking = {
    hostName = "charybdis";
    networkmanager = {
      enable = true;
      plugins = [
        pkgs.networkmanager-openvpn
      ];
    };

    nameservers = [
      # Cloudflare
      "1.1.1.1"
      "1.0.0.1"
      # Quad9
      "9.9.9.9"
      "149.112.112.112"
    ];
  };

  # ---------------- System Packages  ----------------
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gpu-screen-recorder-gtk
  ];
  programs.gpu-screen-recorder.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = false;
  };

  # ---------------- Custom modules ----------------
  hm.enable = true;

  # ---------------- Custom services  ----------------
  virtualisation.docker = {
    enable = true;
  };
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
