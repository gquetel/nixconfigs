{
  lib,
  config,
  nodes,
  ...
}:

with lib;

let
  cfg = config.prometheus;

  # Array of targets, built from hosts with prometheus_exporter.node enabled
  # or false is required for machines that does not declare prometheus_exporter.node.
  prometheusNodeTargets = lib.mapAttrsToList (
    name: node:
    "${node.config.machine.meta.ipTailscale}:${toString node.config.prometheus_exporter.node.port}"
  ) (lib.filterAttrs (name: node: node.config.prometheus_exporter.node.enable or false) nodes);

  nginxNodeTargets = lib.mapAttrsToList (
    name: node:
    "${node.config.machine.meta.ipTailscale}:${toString node.config.prometheus_exporter.nginx.port}"
  ) (lib.filterAttrs (name: node: node.config.prometheus_exporter.nginx.enable or false) nodes);

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
        {
          job_name = "nginx";
          scrape_interval = "60s";
          static_configs = [ { targets = nginxNodeTargets; } ];
        }
      ];
    };
  };
}
