{ lib, config, pkgs, nodes, ... }:
# Module to self-host a mlflow server. 

# I couldn't manage to have nixpkgs mlflow-server working so we are writing 
# our own expression.
# It seems that the packaged mlflow does not include the pre-built UI. Therefore
# we override it by fecthing its wheel and extracting the javascript UI.

let
  cfg = config.mlflow;
  mlflowWheel = pkgs.python3Packages.fetchPypi {
    pname = "mlflow";
    version = pkgs.python3Packages.mlflow.version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-p4oDLPU5KmCLuhpu5ZybvWsdKbLqJZjk4s56IMyvHuo=";
  };

  mlflowUi = pkgs.runCommand "mlflow-ui" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    unzip ${mlflowWheel} "mlflow/server/js/build/*" -d tmp
    mv tmp/mlflow/server/js/build $out
  '';

  # Override mlflow to include the pre-built UI.
  mlflowWithUi = pkgs.python3Packages.mlflow.overridePythonAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/${pkgs.python3.sitePackages}/mlflow/server/js
      cp -r ${mlflowUi} $out/${pkgs.python3.sitePackages}/mlflow/server/js/build
    '';
  });
  
  # The python environment containing mlflow server and its dependencies. 
  pythonEnv = cfg.python.withPackages (ps: [
    mlflowWithUi
    ps.boto3
    ps.mysqlclient
    ps.gunicorn
  ]);

  mlflowWrapper = pkgs.writeShellScriptBin "mlflow-wrapper" ''
    export PATH=${pythonEnv}/bin:$PATH
    export PYTHONPATH="${pythonEnv}/${cfg.python.sitePackages}:$PYTHONPATH"
    exec mlflow server \
      --host ${cfg.host} \
      --port ${toString cfg.port} \
      ${lib.escapeShellArgs cfg.extraArgs}
  '';
in {
  options.mlflow = with lib; {
    enable = mkEnableOption "MLflow tracking server";
    python = mkOption {
      type = types.package;
      default = pkgs.python3;
      description = "Python interpreter to use for MLflow";
    };
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
    port = mkOption {
      type = types.port;
      default = 9909;
    };
    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [
        "--backend-store-uri" "sqlite:////var/lib/mlflow/mlflow.db"
        "--default-artifact-root" "/var/lib/mlflow/artifacts"
      ];
    };
  };

  config = lib.mkIf cfg.enable {

    users.users.mlflow = {
      isSystemUser = true;
      group = "mlflow";
      home = "/var/lib/mlflow";
      createHome = true;
    };
    users.groups.mlflow = {};

    systemd.services.mlflow = {
      description = "MLflow tracking server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${mlflowWrapper}/bin/mlflow-wrapper";
        Restart = "on-failure";
        RestartSec = "30";
        User = "mlflow";
        Group = "mlflow";
        WorkingDirectory = "/var/lib/mlflow";
        StateDirectory = "mlflow";
      };
    };

    services.nginx.virtualHosts."mlflow.mesh.gq" = {
      forceSSL  = true;
      enableACME = true;
      listen = [
        { addr = nodes.strix.config.machine.meta.ipTailscale; port = 443; ssl = true; }
        { addr = nodes.strix.config.machine.meta.ipTailscale; port = 80; }
      ];
      locations."/" = {
        recommendedProxySettings = true;
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    security.acme.certs."mlflow.mesh.gq".server =
      "https://ca.mesh.gq/acme/acme/directory";
  };
}
