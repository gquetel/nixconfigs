{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
# Hermes Agent and its web dashboard.
#
# The agent runs shell commands as the service user, so reaching the UI means
# code execution as that user. nginx (tailnet-only) + oauth2-proxy gate it.
let
  cfg = config.hermes;

  llmAgents = pkgs.callPackage ../../packages/llm-agents {
    inherit inputs;
  };

  hermes = llmAgents."hermes-agent";

  userCfg = config.users.users.${cfg.user};
  homeDir = userCfg.home;

  # Replaces the system PATH for the dashboard and every command the agent
  # runs, so anything it may invoke has to be listed here.
  runtimePath = [ hermes ]
  ++ (with pkgs; [
    git
    gh
    openssh
    bash
    coreutils
    findutils
    gnugrep
    gnused
    gnutar
    gzip
    curl
    jq
    ripgrep
    nodejs
    python3
    uv
  ]);

  # Binding to loopback disables Hermes' own auth gate and makes it reject any
  # Host or Origin that isn't loopback. Both headers are rewritten below.
  loopbackOrigin = "http://127.0.0.1:${toString cfg.port}";

  tailnetOnly = ''
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';

  # Every KEY=VALUE file the agent's environment is built from.
  envFiles =
    lib.optional (cfg.environmentFile != null) cfg.environmentFile
    ++ lib.optional cfg.plane.enable config.age.secrets.hermes-plane-token.path;

  # Upstream bug, if not started on default profile, hermes re-exec itself without 
  # the proper context / dependencies (leading to ModuleNotFound). We start using default 
  # to avoid this.
  dashboardArgs = [
    "-p default"
    "dashboard"
    "--host 127.0.0.1"
    "--port ${toString cfg.port}"
    "--no-open"
    "--skip-build"
  ];

  hermesWrapper = pkgs.writeShellScriptBin "hermes-wrapper" ''
    export SIGNAL_ACCOUNT="$(cat "$CREDENTIALS_DIRECTORY/signal_account")"
    exec ${lib.getExe hermes} ${lib.concatStringsSep " " dashboardArgs}
  '';

  signalCliWrapper = pkgs.writeShellScriptBin "signal-cli-wrapper" ''
    account="$(cat "$CREDENTIALS_DIRECTORY/signal_account")"
    exec ${lib.getExe' pkgs.signal-cli "signal-cli"} --config /var/lib/signal-cli -a "$account" daemon \
      --http 127.0.0.1:${toString cfg.signal.port} \
      --no-receive-stdout
  '';
in
{
  options.hermes = with lib; {
    enable = mkEnableOption "Hermes Agent web dashboard";

    user = mkOption {
      type = types.str;
      default = "gquetel";
      description = ''
        Login user the dashboard and its agents run as. Reaching the ingress is
        a shell as this user; the tailnet ACL and oauth2-proxy limit that.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "hermes.mesh.gq";
      description = "Tailnet-internal hostname serving the UI.";
    };

    port = mkOption {
      type = types.port;
      default = 9119;
      description = "Loopback port of the dashboard, the only one fronted.";
    };

    authPort = mkOption {
      type = types.port;
      default = 9118;
      description = "Loopback port oauth2-proxy listens on.";
    };

    allowedEmails = mkOption {
      type = types.listOf types.str;
      default = [ "gquetel@mail.foo.gq" ];
      description = "Dex identities allowed to reach the dashboard.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = "${config.age.secrets.hermes-provider-keys.path}";
      description = ''
        File of provider credentials (ANTHROPIC_API_KEY, OPENAI_API_KEY, …),
        one KEY=VALUE line each. Set to null to disable; keys can also be
        entered in the dashboard, which stores them under $HOME/.hermes.
      '';
    };

    plane.enable = mkEnableOption ''
      secrets/hermes-plane-token.age as an extra EnvironmentFile, holding the
      Plane API token and whatever else the agent needs to reach the instance
    '';

    # The phone number is PII, so it lives in secrets/hermes-signal-account.age
    # rather than in an option.
    #
    # It must be registered or linked once by hand before first start; the
    # daemon exits with "not registered" otherwise. Run signal-cli's `link`
    # from a transient unit sharing StateDirectory=signal-cli, so the state
    # lands under the same dynamic user:
    #   systemd-run --pty -p DynamicUser=yes -p StateDirectory=signal-cli \
    #     signal-cli --config /var/lib/signal-cli link -n <device-name>
    signal = {
      enable = mkEnableOption "the Signal channel, backed by a local signal-cli daemon";

      port = mkOption {
        type = types.port;
        default = 8090;
        description = "Loopback port the signal-cli JSON-RPC/SSE HTTP daemon listens on.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # `hermes` CLI. Defaults to ~/.hermes, the same state dir as the service.
    environment.systemPackages = [ hermes ];

    systemd.services.hermes = {
      description = "Hermes Agent web dashboard";
      after = [ "network-online.target" ] ++ lib.optional cfg.signal.enable "signal-cli.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = runtimePath;

      environment = {
        # Config, sessions, skills and credentials live under $HOME/.hermes.
        HOME = homeDir;
        HERMES_HOME = "${homeDir}/.hermes";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        # Hermes respawns itself and needs its own binary. Without this it
        # falls back to the bare interpreter, which lacks the dependency
        # paths the wrapper injects.
        HERMES_BIN = lib.getExe hermes;
      }
      # Set together with SIGNAL_ACCOUNT (LoadCredential below) to enable the
      # Signal channel.
      // lib.optionalAttrs cfg.signal.enable {
        SIGNAL_HTTP_URL = "http://127.0.0.1:${toString cfg.signal.port}";
      };

      serviceConfig = {
        ExecStart =
          if cfg.signal.enable then
            lib.getExe hermesWrapper
          else
            lib.concatStringsSep " " ([ (lib.getExe hermes) ] ++ dashboardArgs);
        User = cfg.user;
        Group = userCfg.group;
        WorkingDirectory = homeDir;
        Restart = "on-failure";
        RestartSec = "30";

        # Hardening.
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectSystem = "full"; # /usr, /boot and /etc read-only; $HOME writable.
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
      }
      // lib.optionalAttrs (envFiles != [ ]) {
        EnvironmentFile = envFiles;
      }
      // lib.optionalAttrs cfg.signal.enable {
        LoadCredential = "signal_account:${config.age.secrets.hermes-signal-account.path}";
      };
    };

    systemd.services.oauth2-proxy = {
      after = [ "tailscale-online.service" ];
      requires = [ "tailscale-online.service" ];
    };

    systemd.services.signal-cli = lib.mkIf cfg.signal.enable {
      description = "signal-cli JSON-RPC/SSE daemon for Hermes' Signal channel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = lib.getExe signalCliWrapper;
        LoadCredential = "signal_account:${config.age.secrets.hermes-signal-account.path}";
        DynamicUser = true;
        StateDirectory = "signal-cli";
        Restart = "on-failure";
        RestartSec = "10";

        # Hardening.
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
      };
    };

    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = "https://dex.mesh.gq";
      clientID = "hermes";
      clientSecretFile = config.age.secrets.dex-hermes-secret.path;
      scope = "openid email profile";
      redirectURL = "https://${cfg.host}/oauth2/callback";
      httpAddress = "http://127.0.0.1:${toString cfg.authPort}";
      upstream = [ loopbackOrigin ];
      email.addresses = lib.concatStringsSep "\n" cfg.allowedEmails;
      reverseProxy = true;
      passBasicAuth = false;
      # Keep the loopback Host; Hermes rejects cfg.host.
      passHostHeader = false;
      trustedProxyIP = [
        "127.0.0.1"
        "::1"
      ];
      cookie = {
        secure = true;
        secretFile = config.age.secrets.hermes-cookie-secret.path;
      };
      extraConfig = {
        skip-provider-button = true;
        cookie-samesite = "lax";
        flush-interval = "100ms";
      };
    };

    age.secrets.dex-hermes-secret.file = ../../secrets/dex-hermes-secret.age;
    age.secrets.hermes-cookie-secret.file = ../../secrets/hermes-cookie-secret.age;
    age.secrets.hermes-provider-keys.file = ../../secrets/hermes-provider-keys.age;

    age.secrets.hermes-signal-account = lib.mkIf cfg.signal.enable {
      file = ../../secrets/hermes-signal-account.age;
    };

    age.secrets.hermes-plane-token = lib.mkIf cfg.plane.enable {
      file = ../../secrets/hermes-plane-token.age;
    };

    services.nginx.virtualHosts.${cfg.host} = {
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
        proxyPass = "http://127.0.0.1:${toString cfg.authPort}";
        # Agent events and terminals stream over websockets.
        proxyWebsockets = true;
        extraConfig = tailnetOnly + ''
          # The browser sends the public host; Hermes only accepts loopback.
          proxy_set_header Origin ${loopbackOrigin};

          proxy_buffering off;
          proxy_read_timeout 1d;
          client_max_body_size 0;
        '';
      };
    };
    security.acme.certs.${cfg.host}.server = "https://ca.mesh.gq/acme/acme/directory";
  };
}
