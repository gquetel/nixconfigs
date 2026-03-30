{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.mlflow;
  mlflowPort = 7895;
  artifactsDir = "/portemer/mlflow/artifacts";
  # Use a plain Python environment instead of pkgs.mlflow-server.
  # The nixpkgs mlflow-server package patches process.py to replace
  # sys.executable with a bare gunicornMlflow wrapper, which breaks
  # MLflow 3.x's uvicorn-based server launch.
  mlflowEnv = pkgs.python3.withPackages (ps: with ps; [ mlflow uvicorn ]);
in
{
  options.mlflow = {
    enable = mkEnableOption "MLflow tracking server";
  };

  config = mkIf cfg.enable {
    users.users.mlflow = {
      isSystemUser = true;
      group = "mlflow";
      description = "MLflow service user";
    };
    users.groups.mlflow = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/mlflow 0750 mlflow mlflow -"
      "d ${artifactsDir} 0750 mlflow mlflow -"
    ];

    systemd.services.mlflow = {
      description = "MLflow Tracking Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "tailscale-online.service"
      ];
      requires = [ "tailscale-online.service" ];
      serviceConfig = {
        User = "mlflow";
        Group = "mlflow";
        ExecStart = ''
          ${mlflowEnv}/bin/mlflow server \
            --backend-store-uri sqlite:////var/lib/mlflow/mlflow.db \
            --artifacts-destination ${artifactsDir} \
            --host 127.0.0.1 \
            --port ${toString mlflowPort}
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.nginx.virtualHosts."mlflow.mesh.gq" = {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = config.machine.meta.ipTailscale;
          port = 443;
          ssl = true;
        }
        {
          addr = config.machine.meta.ipTailscale;
          port = 80;
        }
      ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString mlflowPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    security.acme.certs."mlflow.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";
  };
}
