# Backrest: web UI to browse and restore the restic backups on fafnir.
# It uses a read-only Garage key, so it cannot delete snapshots.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.backrest;
in
{
  options.backrest = {
    enable = lib.mkEnableOption "Backrest web UI for restic";

    host = lib.mkOption {
      type = lib.types.str;
      default = "backups.mesh.gq";
      description = "Tailnet-internal hostname serving the UI.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9898;
      description = "Local port of the UI.";
    };

    authPort = lib.mkOption {
      type = lib.types.port;
      default = 4180;
      description = "Local port of the oauth2-proxy in front of the UI.";
    };

    allowedEmails = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "gquetel@mail.foo.gq" ];
      description = "Dex identities allowed to reach the UI.";
    };

    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "strix" ];
      description = "Hosts whose repository restic-<host> Backrest can open.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY of the read-only Garage key backrest.
      "backrest.env".file = ../../secrets/backrest.env.age;
      dex-backrest-secret.file = ../../secrets/dex-backrest-secret.age;
      backrest-cookie-secret.file = ../../secrets/backrest-cookie-secret.age;
    }
    // lib.genAttrs (map (h: "restic-${h}.pwd") cfg.hosts) (name: {
      file = ../../secrets + "/${name}.age";
    });

    systemd.services.backrest = {
      description = "Backrest web UI for restic";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        BACKREST_PORT = "127.0.0.1:${toString cfg.port}";
        BACKREST_DATA = "/var/lib/backrest";
        BACKREST_CONFIG = "/var/lib/backrest/config.json";
        XDG_CACHE_HOME = "/var/cache/backrest";
      };
      serviceConfig = {
        ExecStart = lib.getExe pkgs.backrest;
        DynamicUser = true;
        StateDirectory = "backrest";
        CacheDirectory = "backrest";
        EnvironmentFile = config.age.secrets."backrest.env".path;
        # Readable in the UI as ${CREDENTIALS_DIRECTORY}/restic-<host>.pwd.
        LoadCredential = map (h: "restic-${h}.pwd:${config.age.secrets."restic-${h}.pwd".path}") cfg.hosts;
        Restart = "on-failure";
      };
    };

    # Dex login in front of the UI.
    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = "https://dex.mesh.gq";
      clientID = "backrest";
      clientSecretFile = config.age.secrets.dex-backrest-secret.path;
      scope = "openid email profile";
      redirectURL = "https://${cfg.host}/oauth2/callback";
      httpAddress = "http://127.0.0.1:${toString cfg.authPort}";
      upstream = [ "http://127.0.0.1:${toString cfg.port}" ];
      email.addresses = lib.concatStringsSep "\n" cfg.allowedEmails;
      reverseProxy = true;
      cookie = {
        secure = true;
        secretFile = config.age.secrets.backrest-cookie-secret.path;
      };
      extraConfig.skip-provider-button = true;
    };
    # Dex is reached over the tailnet.
    systemd.services.oauth2-proxy = {
      after = [ "tailscale-online.service" ];
      requires = [ "tailscale-online.service" ];
    };

    tailnet.vhosts.${cfg.host} = {
      proxyPass = "http://127.0.0.1:${toString cfg.authPort}";
      # Operation logs are streamed.
      extraConfig = "proxy_buffering off;";
    };
  };
}
