{
  lib,
  config,
  systemd,
  ...
}:

with lib;

let
  cfg = config.prometheus_exporter;
in
{
  options.prometheus_exporter.node = {
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

  options.prometheus_exporter.nginx = {
    enable = mkEnableOption "NGINX Prometheus exporter service";
    port = mkOption {
      type = types.int;
      default = 9111;
      description = "Port number for NGINX Prometheus exporter to listen on.";
    };

    addr = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for NGINX Prometheus exporter to listen on.";
    };

    scrapeUri = mkOption {
      type = types.str;
      default = "http://localhost/nginx_status";
      description = "URI where NGINX stub_status is available.";
    };
  };

  # Ressources:
  # https://xeiaso.net/blog/prometheus-grafana-loki-nixos-2020-11-20/
  # https://wiki.nixos.org/wiki/Prometheus
  config = mkMerge [
    (
      # Prometheus Node Exporter
      mkIf cfg.node.enable {
        services.prometheus = {
          exporters = {
            node = {
              enable = true;
              enabledCollectors = [ "systemd" ];
              port = cfg.node.port;
              listenAddress = cfg.node.addr;
            };
          };
        };

        # We want to listen on tailscale Ip. We wait that the service is Up.
        # Requires makes it that the service is only started once tailscaled is running.
        systemd.services.prometheus = {
          after = [ "tailscale-online.service" ];
          requires = [ "tailscale-online.service" ];
        };
      }
    )
    # Nginx Node Exporter
    (mkIf cfg.nginx.enable {
      services.prometheus.exporters.nginx = {
        enable = true;
        port = cfg.nginx.port;
        listenAddress = cfg.nginx.addr;
        scrapeUri = cfg.nginx.scrapeUri;
      };

      systemd.services.prometheus-nginx-exporter = {
        after = [ "tailscale-online.service" ];
        requires = [ "tailscale-online.service" ];
      };

      # Enable NGINX stub_status if not already configured
      services.nginx.statusPage = mkDefault true;
    })
  ];
}
