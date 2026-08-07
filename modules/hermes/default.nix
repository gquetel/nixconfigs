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

  # Dependency closure plus Hermes itself, for PYTHONPATH below. The
  # interpreter comes from Hermes' own dependencies because pkgs.python3 is a
  # different minor version.
  hermesPython = (builtins.head hermes.propagatedBuildInputs).pythonModule;
  hermesPythonEnv = hermesPython.withPackages (_: hermes.propagatedBuildInputs);
  hermesPythonPath = lib.concatStringsSep ":" [
    "${hermesPythonEnv}/${hermesPython.sitePackages}"
    "${hermes}/${hermesPython.sitePackages}"
  ];

  userCfg = config.users.users.${cfg.user};
  homeDir = userCfg.home;

  # Replaces the system PATH for the dashboard and every command the agent
  # runs, so anything it may invoke has to be listed here.
  runtimePath = [
    hermes
  ]
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

  # Shared by the dashboard and the gateway: both run the agent as cfg.user
  # against the same $HOME/.hermes state.
  commonUnit = {
    after = [ "network-online.target" ];
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
      # Hermes respawns itself as `sys.executable -m hermes_cli.main`, which
      # is the bare interpreter. The wrapper injects dependencies inside the
      # wrapped script, so only PYTHONPATH reaches such a child.
      PYTHONPATH = hermesPythonPath;
      # Read by the nixos-unit-compat patch: keeps the CLI from rewriting the
      # unit and lets it drive systemd as cfg.user (see the polkit rule).
      # Needed on the dashboard too, which spawns `hermes gateway restart`
      # for its restart button.
      HERMES_NIXOS_UNIT = "1";
    };
  };

  commonServiceConfig = {
    User = cfg.user;
    Group = userCfg.group;
    WorkingDirectory = homeDir;
    Restart = "on-failure";
    RestartSec = "30";
    # Sessions can ignore SIGTERM while a tool call is in flight; kill them
    # well before systemd's 90s default so restarts stay quick.
    TimeoutStopSec = "25";

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
  // lib.optionalAttrs (cfg.environmentFile != null) {
    EnvironmentFile = cfg.environmentFile;
  };
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
  };

  config = lib.mkIf cfg.enable {

    # `hermes` CLI. Defaults to ~/.hermes, the same state dir as the service.
    environment.systemPackages = [ hermes ];
    # So an interactive `hermes gateway ...` takes the same path as the units.
    environment.variables.HERMES_NIXOS_UNIT = "1";

    systemd.services.hermes = {
      description = "Hermes Agent web dashboard";
      inherit (commonUnit)
        after
        wants
        wantedBy
        path
        environment
        ;

      serviceConfig = commonServiceConfig // {
        # --skip-build: the frontend is already built in the package.
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe hermes)
          "dashboard"
          "--host 127.0.0.1"
          "--port ${toString cfg.port}"
          "--no-open"
          "--skip-build"
        ];
      };
    };

    # Serves the messaging channels, which are configured from the dashboard.
    # Separate from the dashboard itself: outside Hermes' s6 container image
    # the two are independent processes.
    systemd.services.hermes-gateway = {
      description = "Hermes Agent messaging gateway";
      inherit (commonUnit)
        after
        wants
        wantedBy
        path
        environment
        ;

      # The directives below mirror the unit Hermes generates for itself; a
      # planned restart (dashboard button, /restart, SIGUSR1) drains and then
      # exits 75 expecting the service manager to bring it back.
      serviceConfig = commonServiceConfig // {
        # --replace takes over from an instance systemd has not reaped yet.
        # --external-supervisor makes in-chat restarts exit back to systemd
        # instead of installing a user-scope unit of Hermes' own.
        ExecStart = "${lib.getExe hermes} gateway run --replace --external-supervisor";
        Restart = "always";
        RestartSec = "5";
        # 78 is Hermes' "config is broken"; restarting cannot fix it.
        RestartPreventExitStatus = "78";
        KillMode = "mixed";
        # Must be >= drain timeout + 30s or the gateway warns at startup that
        # systemd may SIGKILL it mid-drain.
        TimeoutStopSec = "60";
      };
    };

    # Lets the gateway restart itself: the dashboard button and /restart shell
    # out to `hermes gateway restart`, which calls systemctl as cfg.user.
    # Without polkitd running, systemd denies that outright.
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "hermes-gateway.service" &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';

    systemd.services.oauth2-proxy = {
      after = [ "tailscale-online.service" ];
      requires = [ "tailscale-online.service" ];
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
        flush-interval = "100ms";
      };
    };

    age.secrets.dex-hermes-secret.file = ../../secrets/dex-hermes-secret.age;
    age.secrets.hermes-cookie-secret.file = ../../secrets/hermes-cookie-secret.age;
    age.secrets.hermes-provider-keys.file = ../../secrets/hermes-provider-keys.age;

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
