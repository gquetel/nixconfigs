{
  lib,
  config,
  pkgs,
  builtins,
  ...
}:
let
  dexUrl = "dex.mesh.gq";
  dexPort = 9293;
  outlineUrl = "notes.mesh.gq";
in
{
  # From: https://wiki.nixos.org/wiki/Outline
  services.outline = {
    enable = true;
    publicUrl = "https://${outlineUrl}";
    port = 9292;
    forceHttps = false; # Break stuff when set to true.
    storage.storageType = "local";

    # oidc is somehow required, i need to host a dex instance on the machine.
    # TODO: Have this in a separate module and integrate it to other services ?
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
    locations."/" = {
      recommendedProxySettings = true;
      proxyWebsockets = true;
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://localhost:9292";
    };
  };
  security.acme.certs."notes.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";


  # Maybe: https://github.com/outline/outline/discussions/2089
  # To fix dex failure
  services.dex = {
    enable = true;
    settings = {
      issuer = "https://${dexUrl}";
      storage.type = "sqlite3";
      web.http = "127.0.0.1:${toString dexPort}";
      enablePasswordDB = true;
      staticClients = [
        {
          id = "outline";
          name = "Outline Client";
          redirectURIs = [ "https://${outlineUrl}/auth/oidc.callback" ];
          secretFile = config.age.secrets.dex-outline-secret.path;
        }
      ];
      staticPasswords = [
        {
          email = "gquetel@mail.foo.gq";
          # bcrypt hash of the string "password":  htpasswd -BnC 10 admin | cut -d: -f2
          hash = "$2y$10$bNIVUFkMHUmRGtSEdE9UyOcEM/aiIv7Ru0kdMVTGp.GMUO/y/49wy";
          username = "gquetel";
          # easily generated with `$ uuidgen`
          userID = "8c7742f5-e848-46fc-ac8c-c2b6657eced6";
        }
      ];
    };
  };

  services.nginx.virtualHosts."dex.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:${toString dexPort}";
    };
  };
  security.acme.certs."dex.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  age.secrets.dex-outline-secret = {
    file = ../../secrets/dex-outline-secret.age;
    owner = "outline";
    group = "outline";
  };

}
