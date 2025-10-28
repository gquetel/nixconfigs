{ lib, config, nodes, ... }:

with lib;

let
  cfg = config.grafana;
in
{
  options.grafana = {
    enable = mkEnableOption "Grafana monitoring service";

    domain = mkOption {
      type = types.str;
      default = "grafana.mesh.gq";
      description = "Domain name for the Grafana web interface.";
    };

    port = mkOption {
      type = types.int;
      default = 2342;
      description = "Port number for Grafana to listen on.";
    };

    addr = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address Grafana binds to.";
    };
  };
  # Ressources:
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://nixos.wiki/wiki/Grafana

  config = mkIf cfg.enable {
    services.grafana = {
      enable = true;
      domain = cfg.domain;
      port = cfg.port;
      addr = cfg.addr;
    };
    
    services.nginx.virtualHosts.${cfg.domain} = {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = nodes.garmr.config.machine.meta.ipTailscale;
          port = 443;
          ssl = true;
        }
        {
          addr = nodes.garmr.config.machine.meta.ipTailscale;
          port = 80;
        }
      ];
      locations."/" = {
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
        proxyWebsockets = true;
        proxyPass = "http://${cfg.addr}:${toString cfg.port}";
      };
    };

    security.acme.certs."${cfg.domain}" = {
      server = "https://ca.mesh.gq/acme/acme/directory";
    };
  };
}
