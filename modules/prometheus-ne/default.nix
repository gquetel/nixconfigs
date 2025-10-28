{ lib, config, ... }:

with lib;

let
  cfg = config.prometheus_ne;
in
{
  options.prometheus_ne = {
    enable = mkEnableOption "Prometheus node exporter service";

    port = mkOption {
      type = types.int;
      default = 9010;
      description = "Port number for Prometheus Node Exporter to listen on.";
    };

    addr = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for Prometheus Node Exporter to listen on.";
    };

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
          listenAddress = cfg.addr;
        };
      };
    };

  };
}
