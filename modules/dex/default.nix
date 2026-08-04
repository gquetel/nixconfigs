{
  config,
  nodes,
  ...
}:
let
  dexUrl = "dex.mesh.gq";
  dexPort = 9294;
in
{
  # From: https://wiki.nixos.org/wiki/Outline
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
          redirectURIs = [ "https://notes.mesh.gq/auth/oidc.callback" ];
          secretFile = config.age.secrets.dex-outline-secret.path;
        }
        {
          id = "mlflow";
          name = "MLflow Client";
          redirectURIs = [ "https://mlflow.mesh.gq/callback" ];
          secretFile = config.age.secrets.dex-mlflow-secret.path;
        }
        {
          id = "openhands";
          name = "OpenHands Client";
          # Consumed by the oauth2-proxy fronting Agent Canvas on vapula.
          redirectURIs = [ "https://canvas.mesh.gq/oauth2/callback" ];
          secretFile = config.age.secrets.dex-openhands-secret.path;
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
        {
          # Bot used to push data to mlflow-ingest.mesh.gq
          email = "mlflow-bot@foo.gq";
          hash = "$2y$10$sFZWBEdZyjWbhzFMTvvk.O3mRkDYl4HJoUB.AmfNmjX.W9zgZSvZe";
          username = "mlflow-bot";
          userID = "8aeb94b2-305a-47ac-b509-697af055369e";
        }
      ];
    };
  };

  services.nginx.virtualHosts."dex.mesh.gq" = {
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
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:${toString dexPort}";
    };
  };
  security.acme.certs."dex.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  # OpenHands runs on vapula, not strix, so its module (which normally owns
  # this secret) is never imported here to provide it.
  age.secrets.dex-openhands-secret.file = ../../secrets/dex-openhands-secret.age;
}
