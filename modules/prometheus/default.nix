{
  lib,
  config,
  nodes,
  ...
}:

with lib;

let
  cfg = config.prometheus;

  # Array of targets, built from hosts with prometheus_ne enabled
  # or false is required for machines that does not declare prometheus_ne.
  prometheusNodeTargets = lib.mapAttrsToList (
    name: node: "${node.config.machine.meta.ipTailscale}:${toString node.config.prometheus_ne.port}"
  ) (lib.filterAttrs (name: node: node.config.prometheus_ne.enable or false) nodes);

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
              targets = prometheusNodeTargets;
            }
          ];
        }
      ];

    };
  };
}
