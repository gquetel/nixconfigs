{
  lib,
  config,
  pkgs,
  nodes,
  ...
}:
# Module to self-host a mlflow server.

let
  cfg = config.mlflow;
  # Same python package across all built packages here.
  pyPkgs = pkgs.unstable.python3.pkgs;

  # I couldn't manage to have nixpkgs mlflow-server working so we are writing
  # our own expression. It seems that the packaged mlflow does not include the pre-built
  # UI. So first, we override it by fecthing its wheel and extracting the javascript UI.
  mlflowWheel = pyPkgs.fetchPypi {
    pname = "mlflow";
    version = pyPkgs.mlflow.version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-j2vxI4rAT5dmTCKd1IA4DFwlSni9s8DkM+OgOXUIsa8=";
  };
  mlflowUi = pkgs.runCommand "mlflow-ui" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    unzip ${mlflowWheel} "mlflow/server/js/build/*" -d tmp
    mv tmp/mlflow/server/js/build $out
  '';

  # Then, we override mlflow to include the pre-built UI.
  mlflowWithUi = pyPkgs.mlflow.overridePythonAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/${pkgs.unstable.python3.sitePackages}/mlflow/server/js
      cp -r ${mlflowUi} $out/${pkgs.unstable.python3.sitePackages}/mlflow/server/js/build
    '';
  });

  mlflowOidcAuth = pyPkgs.callPackage ./oidc-auth.nix { };

  # Source-IP allowlist applied to the public ingest locations. Matched
  # against the real client IP (PROXY protocol + set_real_ip_from on strix).
  # Empty allowedCIDRs => no IP restriction (mTLS is still required)
  ingestAcl = lib.optionalString (cfg.ingest.allowedCIDRs != [ ]) (
    lib.concatMapStringsSep "\n" (c: "allow ${c};") cfg.ingest.allowedCIDRs + "\ndeny all;\n"
  );

  # ======== SLOPED BUT IT WORKS ========
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
  pythonEnv = pkgs.unstable.python3.withPackages (ps: [
    mlflowWithUi
    mlflowOidcAuth
    ps.boto3
    ps.mysqlclient
    ps.gunicorn
  ]);

  mlflowWrapper = pkgs.writeShellScriptBin "mlflow-wrapper" ''
    export PATH=${pythonEnv}/bin:$PATH
    export PYTHONPATH="${mlflowGroupPlugin}:${pythonEnv}/${pkgs.unstable.python3.sitePackages}:$PYTHONPATH"
    export OIDC_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc_secret")"
    export SECRET_KEY="$(cat "$CREDENTIALS_DIRECTORY/session_key")"
    exec mlflow server \
      --app-name oidc-auth \
      --host ${cfg.host} \
      --port ${toString cfg.port} \
      ${lib.escapeShellArgs cfg.extraArgs}
  '';
in
{
  options.mlflow = with lib; {
    enable = mkEnableOption "MLflow tracking server";
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
        "--backend-store-uri"
        "sqlite:////var/lib/mlflow/mlflow.db"
        "--serve-artifacts"
        # https://mlflow.org/docs/latest/self-hosting/architecture/tracking-server/#tracking-server-artifact-store
        # This can later be changed to a S3 or smth. Right now, local fs.
        "--artifacts-destination"
        "file:///var/lib/mlflow/artifacts"
      ];
    };

    # We declare a public, mTLS-gated ingest endpoint to which computing
    # machines will upload experiments result.
    ingest = {
      enable = mkEnableOption "public mTLS ingest endpoint for off-tailnet clients";
      host = mkOption {
        type = types.str;
        default = "mlflow-ingest.gquetel.fr";
      };

      # step-ca root CA. From: http://ca.mesh.gq/roots.pem
      clientCA = mkOption {
        type = types.path;
      };

      # Source CIDRs allowed through. Should consist of only compute machines.
      allowedCIDRs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

  config = lib.mkIf cfg.enable {

    users.users.mlflow = {
      isSystemUser = true;
      group = "mlflow";
      home = "/var/lib/mlflow";
      createHome = true;
    };
    users.groups.mlflow = { };

    systemd.services.mlflow = {
      description = "MLflow tracking server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        # Required for Python's requests/urllib3 to trust dex.mesh.gq (signed by our instance of step-ca. 
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
        OIDC_DISCOVERY_URL = "https://dex.mesh.gq/.well-known/openid-configuration";
        OIDC_CLIENT_ID = "mlflow";
        OIDC_REDIRECT_URI = "https://mlflow.mesh.gq/callback";
        OIDC_SCOPE = "openid email profile";
        MLFLOW_SERVER_ALLOWED_HOSTS = "mlflow.mesh.gq";
        MLFLOW_SERVER_CORS_ALLOWED_ORIGINS = "https://mlflow.mesh.gq";
        OIDC_GROUP_DETECTION_PLUGIN = "mlflow_dex_groups";
        OIDC_GROUP_NAME = "mlflow-admin";
        OIDC_ADMIN_GROUP_NAME = "mlflow-admin";
        OIDC_PROVIDER_DISPLAY_NAME = "Sign in with Dex";
        AUTOMATIC_LOGIN_REDIRECT = "true";
        SESSION_COOKIE_SECURE = "true";
        MLFLOW_DISABLE_TELEMETRY = "true";
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

        # Security hardening
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectSystem = "strict"; # Whole filesystem read-only; StateDirectory auto-whitelists /var/lib/mlflow.
        PrivateTmp = true; # Rather than add /tmp to statedirectory, we create a service dedicated /tmp.
        ProtectHome = true;
        RemoveIPC = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
      };
    };

    age.secrets.dex-mlflow-secret.file = ../../secrets/dex-mlflow-secret.age;
    age.secrets.mlflow-session-key.file = ../../secrets/mlflow-session-key.age;

    services.nginx.virtualHosts."mlflow.mesh.gq" = {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = nodes.strix.config.machine.meta.ipTailscale;
          port = 443;
          ssl = true;
        }
        {
          addr = nodes.strix.config.machine.meta.ipTailscale;
          port = 80;
        }
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

    security.acme.certs."mlflow.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

    # Public mTLS ingest path for off-tailnet (cluster machines). We enable:
    # - mTLS using our step-ca instance that will issue client certificates.
    # - IP whitelisting (only tailnet machines or machine from cluster can access this route).
    # - Only /api/2.0/mlflow/ (and the artifact API) are proxied.
    services.nginx.virtualHosts.${cfg.ingest.host} = lib.mkIf cfg.ingest.enable {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = "[::]";
          port = 444;
          ssl = true;
          proxyProtocol = true;
        }
        # Allows ACME requests in.
        {
          addr = "[::]";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 80;
        }
      ];
      extraConfig = ''
        ssl_verify_client on;
        ssl_client_certificate ${cfg.ingest.clientCA};
        ssl_verify_depth 2;
      '';
      locations."/api/2.0/mlflow/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        recommendedProxySettings = true;
        extraConfig = ingestAcl;
      };

      # TODO: Check how artifact upload works.
      locations."/api/2.0/mlflow-artifacts/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        recommendedProxySettings = true;
        extraConfig = ingestAcl + ''
          client_max_body_size 0;
        '';
      };
      # Everything else is not exposed publicly.
      locations."/".extraConfig = "return 404;";
    };
  };
}
