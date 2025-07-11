{
  lib,
  config,
  pkgs,
  ...
}:

{

  # Enable firewall
  networking.firewall.enable = true;

  # systemd-resolved: stub resolver, middleware between apps and DNS resolver
  # resolvectl status can be used to see an overview of the resulting DNS setup.
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [
      "9.9.9.9"
      "149.112.112.112"
    ];
    dnsovertls = "true";
  };

  networking.nameservers = [
    # Quad9
    "9.9.9.9"
    "149.112.112.112"
    # FDN
    "80.67.169.12"
    "80.67.169.40"
  ];

  # Use latest kernel version.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable tmux.
  programs.tmux = {
    enable = true;
    clock24 = true;
  };

  # Enable both flakes and nix-command
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Packages to be installed system-wide.
  environment.systemPackages = with pkgs; [
    broot
    btop
    colmena
    dig
    git
    git-lfs
    lazygit
    lsof
    nano
    npins
    ripgrep
    wget
    whois
  ];

  # Memory management service, more aggressive than default oom agent.
  # If avail memory <= 5%, start killing bigger processes.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
  };

}
