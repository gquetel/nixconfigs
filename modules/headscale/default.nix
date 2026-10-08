{
  config,
  nodes,
  pkgs,
  ...
}:
{
  # Headscale server setup. References:
  # - [1] https://headscale.net/stable/setup/requirements/
  # - [2] https://search.nixos.org/options?channel=25.05&from=0&size=50&sort=relevance&type=packages&query=headscale
  # - [3] https://www.youtube.com/watch?v=ph5zQYx3HS8

  services.headscale = {
    enable = true;
    # 0.29.3 or later: the nodeAttrs below need it.
    package = pkgs.unstable.headscale;
    port = 9090;

    settings = {
      policy.path = pkgs.writeText "headscale-policy.json" (
        builtins.toJSON {
          acls = [
            {
              action = "accept";
              src = [ "*" ];
              dst = [ "*:*" ];
            }
            # Exit node traffic. "*:*" only covers tailnet addresses.
            {
              action = "accept";
              src = [ "*" ];
              dst = [ "autogroup:internet:*" ];
            }
          ];
          autoApprovers.exitNode = [ "garmr@" ];
          # iOS and macOS clients 1.102+ only list exit nodes that have this
          # attribute: https://github.com/juanfont/headscale/issues/3415
          nodeAttrs = [
            {
              target = [ "*" ];
              attr = [
                "suggest-exit-node"
                "suggest-exit-node-ui"
              ];
            }
          ];
        }
      );

      # The URL clients will connect to.
      server_url = "https://mesh.gquetel.fr";
      dns = {
        # Base domain to create MagicDNS entries from. Must be different
        # than server_url according to [2]
        base_domain = "mesh.gq";

        # Force the usage of Headscale DNS configuration. We don't need that, the
        # nodes can use their own DNS rather than headscale one.
        override_local_dns = false;
        magic_dns = true;

        # Extra DNS records hardcoded to route to the correct
        # machine in the tailnet.
        extra_records = [
          {
            name = "deluge.mesh.gq";
            type = "A";
            value = nodes.vapula.config.machine.meta.ipTailscale;
          }
          {
            name = "veste.mesh.gq";
            type = "A";
            value = nodes.vapula.config.machine.meta.ipTailscale;
          }
          {
            name = "sonarr.mesh.gq";
            type = "A";
            value = nodes.vapula.config.machine.meta.ipTailscale;
          }
          {
            name = "radarr.mesh.gq";
            type = "A";
            value = nodes.vapula.config.machine.meta.ipTailscale;
          }
          {
            name = "ca.mesh.gq";
            type = "A";
            value = nodes.garmr.config.machine.meta.ipTailscale;
          }
          {
            name = "notes.mesh.gq";
            type = "A";
            value = nodes.strix.config.machine.meta.ipTailscale;
          }

          {
            name = "dex.mesh.gq";
            type = "A";
            value = nodes.strix.config.machine.meta.ipTailscale;
          }
          {
            name = "plane.mesh.gq";
            type = "A";
            value = nodes.garmr.config.machine.meta.ipTailscale;
          }
          {
            name = "wazuh.mesh.gq";
            type = "A";
            value = nodes.garmr.config.machine.meta.ipTailscale;
          }

          {
            name = "mlflow.mesh.gq";
            type = "A";
            value = nodes.strix.config.machine.meta.ipTailscale;
          }

          {
            name = nodes.vapula.config.hermes.host;
            type = "A";
            value = nodes.vapula.config.machine.meta.ipTailscale;
          }

          {
            name = config.grafana.domain;
            type = "A";
            value = nodes.garmr.config.machine.meta.ipTailscale;
          }
        ];
      };
    };
  };

  services.nginx.virtualHosts."mesh.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      # By default 127.0.0.1
      proxyPass = "http://${config.services.headscale.address}:${toString config.services.headscale.port}";
      # Required because we are behind a reverse proxy.
      proxyWebsockets = true;
    };
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      # Plain TLS without PROXY protocol. Headscale must remain directly
      # reachable from strix over the LAN because strix's nginx (which runs the
      # SNI proxy) depends on tailscale-online, and Tailscale needs headscale to
      # be up first — creating a deadlock if all paths go through the SNI proxy.
      # The firewall on garmr restricts port 443 to strix's IPv6 only.
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      # Allows ACME requests in.
      {
        addr = "[::]";
        port = 80;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };
}
