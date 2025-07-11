{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fish
    ../../modules/fonts
    ../../modules/headscale-client
    ../../modules/languagetool
    ../../modules/vscode
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

  # ---------------- Drivers ----------------
  # https://wiki.nixos.org/wiki/NVIDIA
  # For 1050Ti, given this link https://www.nvidia.com/fr-fr/drivers/results/
  # The latest driver version is 570.169 i.e stable, no need to fetch legacy packages:

  hardware.graphics.enable = true;
  # TODO: Implement cache usage
  # services.xserver.videoDrivers = [ "nvidia" ];

  # ---------------- My config  ----------------
  networking.hostName = "hydra";
  deployment = {
    allowLocalDeployment = true;
    targetHost = null; # Disable SSH colmena deployment.
  };

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    packages =
      with pkgs;
      [
        drawio
        element-desktop
        firefox
        gnome-tweaks
        nixfmt-rfc-style
        obsidian
        openvpn
        python311
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
      ]
      ++ [
        (pkgs.callPackage "${(import ../../npins).agenix}/pkgs/agenix.nix" { })
      ];
  };

  # ---------- Custom modules ----------

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
