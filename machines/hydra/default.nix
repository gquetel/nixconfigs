{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/vscode
    ../../modules/fish
    ../../modules/fonts
    ../../modules/languagetool
    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # ---------------- Automatically generated  ----------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Brussels";
  i18n.defaultLocale = "en_GB.UTF-8";
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

  # hardware.opengl = {
  #   enable = true;
  #   extraPackages = with pkgs; [
  #     intel-media-driver # LIBVA_DRIVER_NAME=iHD
  #   ];
  # };
  # ---------------- My config  ----------------
  networking.hostName = "hydra";
  deployment = {
    allowLocalDeployment = true;
    targetHost = null; # Disable SSH colmena deployment.
  };

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

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    nano
  ];

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    packages = with pkgs; [
      broot
      colmena
      drawio
      lazygit
      element-desktop
      firefox
      git
      git-lfs
      gnome-tweaks
      btop
      nixfmt-rfc-style
      npins
      obsidian
      openvpn
      python311
      ripgrep
      signal-desktop
      spotify
      texliveFull
      tmux
      thunderbird
      tinymist
      typst
      typstfmt
      zotero
      zoom-us
    ];
};

  # ---------- Custom modules ----------
  vscode = {
    enable = true;
    user = "gquetel";
  };
  fish.enable = true;
  languagetool.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
