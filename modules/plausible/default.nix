{
  lib,
  config,
  nodes,
  ...
}:

with lib;

let
  cfg = config.plausible;
in
{
  options.plausible = {
    enable = mkEnableOption "Enable plausible analytics service.";

  };

  config = mkIf cfg.enable {
    services.plausible = {
      enable = true;
      server = {
        baseUrl = "https://argus.gquetel.fr";
        port = 8455;
        secretKeybaseFile = config.age.secrets.plausible-secret-key-base.path;
      };
    };

    services.nginx.virtualHosts = {
      "argus.gquetel.fr" = {
        forceSSL = true;
        enableACME = true;
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
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://localhost:${toString config.services.plausible.server.port}";
        };
      };
    };

    age.secrets = {
      plausible-secret-key-base.file = ../../secrets/plausible-secret-key-base.age;
    };
  };

}
