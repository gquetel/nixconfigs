{ lib, config, ... }:

with lib;

let
  cfg = config.plausible;

  # ClickHouse internal log tables. They have no TTL by default, and each
  # ClickHouse upgrade keeps the old table as <name>_N.
  clickhouseSystemLogs = [
    "aggregated_zookeeper_log"
    "asynchronous_insert_log"
    "asynchronous_metric_log"
    "background_schedule_pool_log"
    "backup_log"
    "blob_storage_log"
    "delta_lake_metadata_log"
    "error_log"
    "iceberg_metadata_log"
    "instrumentation_trace_log"
    "metric_log"
    "opentelemetry_span_log"
    "part_log"
    "processors_profile_log"
    "query_log"
    "query_metric_log"
    "query_thread_log"
    "query_views_log"
    "session_log"
    "text_log"
    "trace_log"
    "zookeeper_connection_log"
    "zookeeper_log"
  ];
in
{
  options.plausible = {
    enable = mkEnableOption "Enable plausible analytics service.";

  };

  config = mkIf cfg.enable {
    services.plausible = {
      enable = true;
      server = {
        baseUrl = "https://argus.gquetel.fr";
        port = 8455;
        secretKeybaseFile = config.age.secrets.plausible-secret-key-base.path;
      };
    };

    # Disable ClickHouse internal log tables, as in Plausible's own self-hosting setup.
    services.clickhouse.extraServerConfig = ''
      <clickhouse>
      ${concatMapStringsSep "\n" (name: "  <${name} remove=\"remove\"/>") clickhouseSystemLogs}
      </clickhouse>
    '';

    services.nginx.virtualHosts = {
      "argus.gquetel.fr" = {
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
          proxyWebsockets = true;
          proxyPass = "http://localhost:${toString config.services.plausible.server.port}";
        };
      };
    };

    age.secrets = {
      plausible-secret-key-base.file = ../../secrets/plausible-secret-key-base.age;
    };
  };

}
