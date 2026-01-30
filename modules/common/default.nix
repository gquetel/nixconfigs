{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.common;
in
{

  options = {
    common.useLatestKernel = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to use the latest kernel packages";
    };
  };

  options.machine.meta = lib.mkOption {
    description = "Machine metadata";

    type = lib.types.submodule {
      # We allow for freeform options.
      # https://nixos.org/manual/nixos/stable/#sec-freeform-modules
      freeformType = with lib.types; attrsOf str;

      options.ipTailscale = lib.mkOption {
        type = lib.types.str;
        default = null;
      };
    };
  };

  config = {
    security.pki.certificates = [
      # custom step-ca root public certificate file.
      # Required if i want my machines to trust certificates issued by my step-ca instance.

      # Root CA generated manually
      ''
        -----BEGIN CERTIFICATE-----
        MIIBdTCCARqgAwIBAgIRAPOAKlBcE/h/LuxFpQeINF4wCgYIKoZIzj0EAwIwGDEW
        MBQGA1UEAxMNZ2FybXIgUm9vdCBDQTAeFw0yNTA3MTQxMDExMzRaFw0zNTA3MTIx
        MDExMzRaMBgxFjAUBgNVBAMTDWdhcm1yIFJvb3QgQ0EwWTATBgcqhkjOPQIBBggq
        hkjOPQMBBwNCAASKpNvqsVINura1WrF9bcj9hwTmKlbLZ2PA2Oc7rCROHCvrjAD5
        0D2TFMi/5jHlLbKM5AoYu/4AMrg+EsxmgULGo0UwQzAOBgNVHQ8BAf8EBAMCAQYw
        EgYDVR0TAQH/BAgwBgEB/wIBATAdBgNVHQ4EFgQUi6Hlc5zrjPuDVJkzcliP4OEI
        hIgwCgYIKoZIzj0EAwIDSQAwRgIhAIquFboD0RZbpfRCmQur2qsw8Bk+d504IyNn
        nA6kaXCXAiEAzJj3anHJZxCNi2UpSMfQKyACd/W7c56y+FcTOjvgPjM=
        -----END CERTIFICATE-----
      ''
    ];

    # Enable firewall
    networking.firewall.enable = true;

    # Use latest kernel version.
    boot.kernelPackages = mkIf cfg.useLatestKernel pkgs.linuxPackages_latest;

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

    # Automatic garbe collection
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # Show which package provide this command. Per [1:  you need to make sure that
    # root’s channels include a channel named nixos:

    # nix-channel --add https://nixos.org/channels/nixos-unstable nixos
    # sudo nix-channel --update
    # - [1] https://discourse.nixos.org/t/command-not-found-unable-to-open-database/3807
    programs.command-not-found.enable = true;

    # https://wiki.nixos.org/wiki/Fonts#Configuring_fonts
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        hack-font
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];

      fontconfig = {
        defaultFonts = {
          serif = [
            "Noto Serif"
            "Noto Color Emoji"
          ];
          sansSerif = [
            "Noto Sans"
            "Noto Color Emoji"
          ];
          monospace = [
            "hack-font"
            "Noto Color Emoji"
          ];
        };
      };
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
  };

}
