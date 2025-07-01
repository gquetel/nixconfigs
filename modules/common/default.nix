{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.common;
  unstable = pkgs.unstable;
in
{
  options.common = {
    enable = lib.mkEnableOption "Common configuration for all my machines.";
  };
  config = lib.mkIf cfg.enable {

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
      git
      git-lfs
      lazygit
      nano
      npins
      ripgrep
      wget
    ];

  };
}
