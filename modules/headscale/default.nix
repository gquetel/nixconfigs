{
  lib,
  config,
  pkgs,
  nodes,
  ...
}:
{
  # Headscale server setup. References:
  # - [1] https://headscale.net/stable/setup/requirements/
  # - [2] https://search.nixos.org/options?channel=25.05&from=0&size=50&sort=relevance&type=packages&query=headscale
  # - [3] https://www.youtube.com/watch?v=ph5zQYx3HS8

  services.headscale = {
    enable = true;

    # Listening address + port of headscale.
    address = "0.0.0.0";
    port = 9090;

    settings = {
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
            name = config.grafana.domain;
            type = "A";
            value = nodes.garmr.config.machine.meta.ipTailscale;
          }
        ];
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "gregor.quetel@gquetel.fr";
  };

  services.nginx.virtualHosts."mesh.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9090";
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
