{ lib, config, ... }:

with lib;

let
  cfg = config.prometheus;
in
{
  options.prometheus = {
    enable = mkEnableOption "Prometheus metrics management service";

    # domain = mkOption {
    #   type = types.str;
    #   default = "grafana.mesh.gq";
    #   description = "Domain name for the Grafana web interface.";
    # };

    port = mkOption {
      type = types.int;
      default = 9009;
      description = "Port number for Grafana to listen on.";
    };

    # addr = mkOption {
    #   type = types.str;
    #   default = "127.0.0.1";
    #   description = "Address Grafana binds to.";
    # };
  };
  # Ressources:
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://wiki.nixos.org/wiki/Prometheus

  config = mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;

      scrapeConfigs = [
        {
          job_name = "garmr-systemd";
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
            }
          ];
        }
      ];

    };
  };
}
