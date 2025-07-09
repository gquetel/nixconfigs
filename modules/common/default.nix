{
  lib,
  config,
  pkgs,
  ...
}:

{

  # Enable firewall
  networking.firewall.enable = true;

  # Use latest kernel version.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable tmux.
  programs.tmux = {
    enable = true;
    clock24 = true;
  };

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
