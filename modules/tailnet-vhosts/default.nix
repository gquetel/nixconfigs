{ config, lib, ... }:
let
  cfg = config.tailnet.vhosts;
  ip = config.machine.meta.ipTailscale;
in
{
  options.tailnet.vhosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    default = { };
    example = {
      "app.mesh.gq" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
      };
    };
    description = ''
      Nginx vhosts that only tailnet peers can reach. Each vhost listens on
      the Tailscale IP of this host and gets its certificate from step-ca.
      The value is the `/` location; the tailnet ACL comes before its
      `extraConfig`.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    services.nginx.virtualHosts = lib.mapAttrs (_: location: {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = ip;
          port = 443;
          ssl = true;
        }
        {
          addr = ip;
          port = 80;
        }
      ];
      locations."/" = location // {
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        ''
        + location.extraConfig or "";
      };
    }) cfg;

    security.acme.certs = lib.mapAttrs (_: _: {
      server = "https://ca.mesh.gq/acme/acme/directory";
    }) cfg;
  };
}
