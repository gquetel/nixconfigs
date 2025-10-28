{ lib, config, nodes, ... }:

with lib;

let
  cfg = config.prometheus;
in
{
  options.prometheus = {
    enable = mkEnableOption "Prometheus metrics management service";

    port = mkOption {
      type = types.int;
      default = 9009;
      description = "Port number for Grafana to listen on.";
    };
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
          job_name = "cluster-systemd";
          static_configs = [
            {
              targets = [ "${nodes.garmr.config.deployment.targetHost}:${toString config.services.prometheus.exporters.node.port}" ];
            }
          ];
        }
      ];

    };
  };
}
