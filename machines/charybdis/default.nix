{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fish
    ../../modules/firefox
    ../../modules/fonts
    ../../modules/tailscale
    ../../modules/languagetool
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
  # TODO
  # This computer possess 2 GPUs: A 1050Ti, and an integrated iHD 630
  # - The NVIDIA card still receive driver updates, which can be enabled using this doc:
  # https://wiki.nixos.org/wiki/NVIDIA
  # - To enable the iGPU, I had to enable it in the BIOS of the computer.

  # Only then "lspci -d ::03xx" is able to find both:
  # 00:02.0 Display controller: Intel Corporation HD Graphics 630 (rev 04)
  # 01:00.0 VGA compatible controller: NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] (rev a1)

  # From there, i can setup PRIME to solely use the GPU for intensive tasks, and the
  # iGPU for window management.
  # TODO: This currently does not work. While both GPUs can be accessed, X server uses
  # the NVIDIA card.

  hardware.graphics = {
    enable = true;
  };

  # TODO: Fix this
  # hardware.nvidia = {
  #   open = false; # setting to true break correct display.
  #   prime = {
  #     intelBusId = "PCI:0:2:0";
  #     nvidiaBusId = "PCI:1:0:0";
  #     sync.enable = true;
  #   };
  # };

  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    xkb = {
      layout = "fr";
      variant = "azerty";
    };

    videoDrivers = [
      "nvidia"
      # modesetting is needed for offloading, otherwise the X-server is run on the nvidia card
      "modesetting"
    ];
  };

  # ---------------- My config  ----------------
  machine.meta = {
    # TODO: Update
    ipTailscale = "100.64.0.1";
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

    packages =
      with pkgs;
      [
        discord
        drawio
        element-desktop
        gnome-tweaks
        atlauncher
        prismlauncher
        hmcl
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
        typstyle
        vlc
        zotero
        zoom-us
      ]
      ++ [
        (pkgs.callPackage "${(import ../../npins).agenix}/pkgs/agenix.nix" { })
      ];
  };

  # ---------------- Networking  ----------------
  networking = {
    hostName = "hydra";
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
