{ lib, config, ... }:

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
    age.secrets.grafana-secret-key = {
      file = ../../secrets/grafana-secret-key.age;
      owner = "grafana";
      group = "grafana";
    };

    services.grafana = {
      enable = true;
      settings.server = {
        domain = cfg.domain;
        http_port = cfg.port;
        http_addr = cfg.addr;
      };
      settings.security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
    };

    tailnet.vhosts.${cfg.domain} = {
      proxyWebsockets = true;
      proxyPass = "http://${cfg.addr}:${toString cfg.port}";
    };
  };
}
