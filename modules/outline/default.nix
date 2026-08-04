{
  lib,
  config,
  pkgs,
  nodes,
  builtins,
  ...
}:
let
  dexUrl = "dex.mesh.gq";
  outlineUrl = "notes.mesh.gq";
in
{
  # From: https://wiki.nixos.org/wiki/Outline
  services.outline = {
    enable = true;
    package = pkgs.unstable.outline;
    publicUrl = "https://${outlineUrl}";
    port = 9292;
    forceHttps = false; # Break stuff when set to true.
    storage.storageType = "local";

    # oidc is somehow required, i need to host a dex instance on the machine.
    oidcAuthentication = {
      authUrl = "https://${dexUrl}/auth";
      tokenUrl = "https://${dexUrl}/token";
      userinfoUrl = "https://${dexUrl}/userinfo";
      clientId = "outline";
      # File containing a private string used to authenticate the app to
      # the identity provider (dex).
      clientSecretFile = config.age.secrets.dex-outline-secret.path;
      scopes = [
        "openid"
        "email"
        "profile"
      ];
      usernameClaim = "preferred_username";
      displayName = "Dex";
    };
  };

  services.nginx.virtualHosts."notes.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = nodes.strix.config.machine.meta.ipTailscale;
        port = 443;
        ssl = true;
      }
      {
        addr = nodes.strix.config.machine.meta.ipTailscale;
        port = 80;
      }
    ];
    locations."/" = {
      recommendedProxySettings = true;
      # Required, else break editing:
      # https://github.com/outline/outline/discussions/3546
      proxyWebsockets = true;

      extraConfig = ''
        allow 100.64.0.0/10;
        allow  fd7a:115c:a1e0::/48;
        deny all;'';
      proxyPass = "http://localhost:9292";
    };
  };
  security.acme.certs."notes.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  age.secrets.dex-outline-secret = {
    file = ../../secrets/dex-outline-secret.age;
    owner = "outline";
    group = "outline";
  };
}
