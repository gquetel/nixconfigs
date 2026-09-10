{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.uptime-kuma;
in
{
  options.uptime-kuma = {
    enable = mkEnableOption "Uptime Kuma status page and monitoring service";

    domain = mkOption {
      type = types.str;
      default = "status.gquetel.fr";
      description = "Public domain name of the status page.";
    };

    port = mkOption {
      type = types.int;
      default = 3001;
      description = "Loopback port that Uptime Kuma listens on.";
    };

    addr = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address that Uptime Kuma binds to.";
    };
  };

  config = mkIf cfg.enable {
    services.uptime-kuma = {
      enable = true;
      settings = {
        HOST = cfg.addr;
        PORT = toString cfg.port;
      };
    };

    services.nginx.virtualHosts.${cfg.domain} = {
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
        proxyPass = "http://${cfg.addr}:${toString cfg.port}";
      };
    };
  };
}
