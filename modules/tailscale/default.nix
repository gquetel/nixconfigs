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
    package = pkgs.unstable.tailscale;
  };

  networking.firewall = {
    # Disable reverse path via same interface packet filtering
    checkReversePath = "loose";
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # This creates a service "tailscale-online" that is up once we can bind the tailscale IPv4.
  # https://github.com/tailscale/tailscale/issues/11504
  # We don't simply rely on tailscaled.service because it is up before the IP is bindable.
  systemd.services.tailscale-online = {
    description = "Wait for Tailscale to have an IPv4 address";

    # [Unit]
    requires = [ "systemd-networkd.service" ];
    after = [ "systemd-networkd.service" ];

    # [Service]
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online -i tailscale0 -4";
    };
  };

  # A client is added using the command:
  # sudo tailscale up --login-server headscale_server_url
}
