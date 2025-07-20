{
  lib,
  config,
  pkgs,
  ...
}:

{
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
