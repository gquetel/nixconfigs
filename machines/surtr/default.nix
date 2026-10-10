# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/firefox
    ../../modules/fish
    ../../modules/fonts
    ../../modules/tailscale
    ../../modules/home-manager
    ../../modules/wazuh-agent
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

  services.xserver = {
    enable = true;
    xkb = {
      layout = "fr";
      variant = "azerty";
    };
  };

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
    ipTailscale = "100.64.0.7";
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

  networking = {
    hostName = "surtr";
    networkmanager = {
      enable = true;
      plugins = [
        pkgs.networkmanager-openvpn
      ];
    };
    nameservers = [
      "80.67.169.12"
      "1.1.1.1"
      "9.9.9.9"

      "80.67.169.40"
      "1.0.0.1"
      "149.112.112.112"
    ];
  };

  # ---------------- Drivers ----------------
  # GPU drivers: fill in after install, based on `lspci | grep VGA` on the
  # real hardware (see machines/scylla/default.nix for an Intel example).

  # Intel Wireless-AC 9560 (CNVi): firmware hangs after a few minutes and the
  # card stays dead until a full power-off. Disable its power saving.
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0 uapsd_disable=1
    options iwlmvm power_scheme=1
  '';

  users.users.gquetel = {
    isNormalUser = true;
    description = "gquetel";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "video"
    ];
  };

  # ---------------- Custom modules ----------------
  hm.enable = true;

  # This is so that agenix decrypts with the SSH host key. We enable
  # openssh but don't open firewall nor enable auth.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.PasswordAuthentication = false;
  };

  # ---------------- Custom services  ----------------
  environment.systemPackages = with pkgs; [
    gnome-tweaks
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05";
}
