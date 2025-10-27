{ lib, config, ... }:

with lib;

let
  cfg = config.prometheus_ne;
in
{
  options.prometheus_ne = {
    enable = mkEnableOption "Prometheus node exporter service";

    # domain = mkOption {
    #   type = types.str;
    #   default = "grafana.mesh.gq";
    #   description = "Domain name for the Grafana web interface.";
    # };

    port = mkOption {
      type = types.int;
      default = 9010;
      description = "Port number for Prometheus Node Exporter to listen on.";
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
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
          port = cfg.port;
        };
      };
    };

  };
}
