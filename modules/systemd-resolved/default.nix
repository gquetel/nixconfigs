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
    dnssec = "true";
    # These domains are used as search suffixes 
    domains = ["mesh.gq"];
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
}
