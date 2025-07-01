{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Headscale server setup. Via: 
  # - [1] https://headscale.net/stable/setup/requirements/
  # - [2] https://search.nixos.org/options?channel=25.05&from=0&size=50&sort=relevance&type=packages&query=headscale

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
        base_domain = "gquetel.mesh";
      };
    };
  };

  # Headscale requires to be served on port 443 according to [1]
  # I use nginx to do that. 
  services.nginx = {
    enable = true;
    logError = "/var/log/nginx/error.log error";
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
      proxyWebsockets = true;
    };
  };
}
