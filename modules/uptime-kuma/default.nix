{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.uptime-kuma;
  domain = "status.gquetel.fr";
  port = 3001;
  addr = "127.0.0.1";
in
{
  options.uptime-kuma.enable = mkEnableOption "Uptime Kuma status page and monitoring service";

  config = mkIf cfg.enable {
    services.uptime-kuma = {
      enable = true;
      settings = {
        HOST = addr;
        PORT = toString port;
      };
    };

    services.nginx.virtualHosts.${domain} = {
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
        # The dashboard speaks socket.io.
        proxyWebsockets = true;
        proxyPass = "http://${addr}:${toString port}";
      };
    };
  };
}
