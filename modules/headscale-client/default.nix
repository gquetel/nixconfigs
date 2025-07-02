{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Headscale client setup.
  services.tailscale = {
    enable = true;
  };

  networking.firewall = {
    # Disable reverse path via same interface packet filtering
    checkReversePath = "loose";
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
