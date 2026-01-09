{
  lib,
  config,
  pkgs,
  ...
}:

{
  # systemd-resolved: stub resolver, middleware between apps and DNS resolver
  # resolvectl status can be used to see an overview of the resulting DNS setup.
  services.resolved = {
    enable = true;
    # dnssec = "true";
    # These domains are used as search suffixes
    domains = [ "mesh.gq" ];
    fallbackDns = [
      "80.67.169.12"
      "1.1.1.1"
      "80.67.169.40"

      "9.9.9.9"
      "1.0.0.1"
      "149.112.112.112"
    ];
    dnsovertls = "true";
  };

  networking.nameservers = [
    "80.67.169.12"
    "1.1.1.1"
    "9.9.9.9"

    "80.67.169.40"
    "1.0.0.1"
    "149.112.112.112"
  ];
}
