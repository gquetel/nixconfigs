{
  lib,
  config,
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

        # Force the usage of Headscale DNS configuration.
        override_local_dns = true;
        magic_dns = true;

        # Extra DNS records hardcoded to route to the correct
        # machine in the tailnet.
        extra_records = [
          {
            name = "deluge.mesh.gq";
            type = "A";
            value = "100.64.0.2";
          }
          {
            name = "veste.mesh.gq";
            type = "A";
            value = "100.64.0.2";
          }
          {
            name = "sonarr.mesh.gq";
            type = "A";
            value = "100.64.0.2";
          }
          {
            name = "radarr.mesh.gq";
            type = "A";
            value = "100.64.0.2";
          }
          {
            name = "ca.mesh.gq";
            type = "A";
            value = "100.64.0.5";
          }
          {
            name = "notes.mesh.gq";
            type = "A";
            value = "100.64.0.3";
          }

          {
            name = "dex.mesh.gq";
            type = "A";
            value = "100.64.0.3";
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
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };
}
