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
    xkb = {
      layout = "fr";
      variant = "azerty";
    };

    videoDrivers = [ "nvidia" ];
  };

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # ---------------- My config  ----------------
  machine.meta = {
    # TODO: Update
    ipTailscale = "100.64.0.9";
  };

  # Use stable kernel for better NVIDIA driver compatibility

  common.useLatestKernel = false;
  boot.kernelPackages = pkgs.linuxPackages;

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
      hmcl
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

  # ---------------- openssh ----------------
  # Enabled for its host key, which agenix uses to decrypt secrets. The port
  # stays closed, except on the trusted tailscale0 interface.
  # TODO: Wazuh agent. After the first deploy with openssh, add
  # /etc/ssh/ssh_host_ed25519_key.pub as system-charybdis to `workstations` in
  # secrets/secrets.nix, encrypt wazuh-authd.pass.age again, then import
  # ../../modules/wazuh-agent (as on scylla). `agenix -e` does not rewrite an
  # unchanged secret; in secrets/, use:
  #   agenix -d wazuh-authd.pass.age | age -o wazuh-authd.pass.age.new \
  #     -R <(nix-instantiate --eval --strict --json -E \
  #       '(import ./secrets.nix)."wazuh-authd.pass.age".publicKeys' | jq -r '.[]')
  #   mv wazuh-authd.pass.age.new wazuh-authd.pass.age
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.PasswordAuthentication = false;
  };

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
