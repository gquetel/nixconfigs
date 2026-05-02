{ lib, config, pkgs, nodes, ... }:
# Module to self-host a mlflow server. 


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
  # I couldn't manage to have nixpkgs mlflow-server working so we are writing 
  # our own expression. It seems that the packaged mlflow does not include the pre-built 
  # UI. Therefore we override it by fecthing its wheel and extracting the javascript UI.

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

  mlflowOidcAuth = pkgs.python3Packages.callPackage ./oidc-auth.nix { };

  # Dex's local connector emits no `groups` claim, and the plugin's fallback
  # of reading a string-valued claim corrupts the DB (it iterates the value
  # character-by-character — see auth.py:handle_user_and_group_management).
  # The hook below is what OIDC_GROUP_DETECTION_PLUGIN expects: a module with
  # a `get_user_groups(access_token)` callable returning a list. Because dex's
  # static-password DB only contains gquetel, every successful login is
  # implicitly admin.
  mlflowGroupPlugin = pkgs.writeTextDir "mlflow_dex_groups.py" ''
    def get_user_groups(access_token):
        return ["mlflow-admin"]
  '';

  # The python environment containing mlflow server and its dependencies.
  pythonEnv = cfg.python.withPackages (ps: [
    mlflowWithUi
    mlflowOidcAuth
    ps.boto3
    ps.mysqlclient
    ps.gunicorn
  ]);

  mlflowWrapper = pkgs.writeShellScriptBin "mlflow-wrapper" ''
    export PATH=${pythonEnv}/bin:$PATH
    export PYTHONPATH="${mlflowGroupPlugin}:${pythonEnv}/${cfg.python.sitePackages}:$PYTHONPATH"
    export OIDC_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc_secret")"
    export SECRET_KEY="$(cat "$CREDENTIALS_DIRECTORY/session_key")"
    exec mlflow server \
      --app-name oidc-auth \
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
      environment = {
        # Python's requests/urllib3 use certifi's bundle by default and won't
        # trust dex.mesh.gq (signed by step-ca). We point to the system
        # bundle, which includes the step-ca root via security.pki.certificates.
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
        OIDC_DISCOVERY_URL = "https://dex.mesh.gq/.well-known/openid-configuration";
        OIDC_CLIENT_ID = "mlflow";
        OIDC_REDIRECT_URI = "https://mlflow.mesh.gq/callback";
        # Space-separated per OAuth2 spec; plugin passes the value verbatim
        # to authlib. Its own default ("openid,email,profile") is upstream-buggy.
        OIDC_SCOPE = "openid email profile";
        OIDC_GROUP_DETECTION_PLUGIN = "mlflow_dex_groups";
        OIDC_GROUP_NAME = "mlflow-admin";
        OIDC_ADMIN_GROUP_NAME = "mlflow-admin";
        OIDC_PROVIDER_DISPLAY_NAME = "Sign in with Dex";
        AUTOMATIC_LOGIN_REDIRECT = "true";
        SESSION_COOKIE_SECURE = "true";
      };
      serviceConfig = {
        ExecStart = "${mlflowWrapper}/bin/mlflow-wrapper";
        Restart = "on-failure";
        RestartSec = "30";
        User = "mlflow";
        Group = "mlflow";
        WorkingDirectory = "/var/lib/mlflow";
        StateDirectory = "mlflow";
        LoadCredential = [
          "oidc_secret:${config.age.secrets.dex-mlflow-secret.path}"
          "session_key:${config.age.secrets.mlflow-session-key.path}"
        ];

        # Some security hardening
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        # ProtectSystem = "strict"; # Which exception should be added ?
      };
    };

    age.secrets.dex-mlflow-secret.file = ../../secrets/dex-mlflow-secret.age;
    age.secrets.mlflow-session-key.file = ../../secrets/mlflow-session-key.age;

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
