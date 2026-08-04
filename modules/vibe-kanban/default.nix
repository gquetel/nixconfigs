{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
# The binary has no auth and no CSRF protection, so reaching it means code
# execution as the service user. nginx (tailnet-only) + oauth2-proxy (dex)
# gate access before the loopback port.

let
  cfg = config.vibe-kanban;
  llmAgents = pkgs.callPackage ../../packages/llm-agents {
    inherit inputs;
  };
  vibe-kanban = llmAgents."vibe-kanban";
  claude-code = llmAgents."claude-code";
  codex = llmAgents.codex;

  userCfg = config.users.users.${cfg.user};
  homeDir = userCfg.home;
  dataDir = "${homeDir}/.local/share/vibe-kanban";

  # Overrides merged over crates/executors/default_profiles.json, else
  # CLAUDE_CODE/CODEX shell out to `npx` instead of the Nix packages.
  # merge_with_defaults replaces a variant wholesale, so defaults are repeated.
  defaultProfiles = pkgs.writeText "vibe-kanban-profiles.json" (
    builtins.toJSON {
      executors = {
        CLAUDE_CODE.DEFAULT.CLAUDE_CODE = {
          dangerously_skip_permissions = true;
          base_command_override = lib.getExe claude-code;
        };
        CODEX.DEFAULT.CODEX = {
          sandbox = "danger-full-access";
          base_command_override = lib.getExe codex;
        };
      };
    }
  );

  # PATH for the server and every agent it spawns.
  runtimePath = with pkgs; [
    claude-code
    codex
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
  ];

  preStart = pkgs.writeShellScript "vibe-kanban-pre-start" ''
    install -d -m0700 ${dataDir}

    # Seeded once so the executor overrides can still be edited from the UI.
    if [ ! -e ${dataDir}/profiles.json ]; then
      install -m0600 ${defaultProfiles} ${dataDir}/profiles.json
    fi

    # Server defaults both to true in config.json. Both are no-ops now (no
    # PostHog key / relay base in this build) — set false against a later version.
    if [ -e ${dataDir}/config.json ]; then
      ${pkgs.jq}/bin/jq '.relay_enabled = false | .analytics_enabled = false' \
        ${dataDir}/config.json > ${dataDir}/config.json.new \
        && mv ${dataDir}/config.json.new ${dataDir}/config.json
    fi
  '';

  startScript = pkgs.writeShellScript "vibe-kanban-start" ''
    export CLAUDE_CODE_OAUTH_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/claude-token")"
    exec ${lib.getExe vibe-kanban}
  '';

  tailnetOnly = ''
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';
in
{
  options.vibe-kanban = with lib; {
    enable = mkEnableOption "vibe-kanban server";

    user = mkOption {
      type = types.str;
      default = "gquetel";
      description = ''
        Login user the server and its agents run as. Reaching the server is
        a shell as this user; the tailnet ACL and oauth2-proxy limit that.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "kanban.mesh.gq";
      description = "Tailnet-internal hostname serving the UI.";
    };

    port = mkOption {
      type = types.port;
      default = 9910;
      description = "Loopback port for the vibe-kanban API and UI.";
    };

    previewProxyPort = mkOption {
      type = types.port;
      default = 9911;
      description = ''
        Loopback port for the preview proxy fronting agent dev servers.
        Pinned instead of the default 0 (random port); not exposed through nginx.
      '';
    };

    authPort = mkOption {
      type = types.port;
      default = 9912;
      description = "Loopback port oauth2-proxy listens on.";
    };

    allowedEmails = mkOption {
      type = types.listOf types.str;
      default = [ "gquetel@mail.foo.gq" ];
      description = "Dex identities allowed to reach the server.";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.services.vibe-kanban = {
      description = "vibe-kanban server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = runtimePath;

      environment = {
        HOST = "127.0.0.1";
        BACKEND_PORT = toString cfg.port;
        PREVIEW_PROXY_PORT = toString cfg.previewProxyPort;
        # Needed for XDG dir resolution. Left at default so state matches
        # an interactive run.
        HOME = homeDir;
        RUST_LOG = "info";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };

      serviceConfig = {
        ExecStartPre = preStart;
        ExecStart = startScript;
        User = cfg.user;
        Group = userCfg.group;
        WorkingDirectory = homeDir;
        Restart = "on-failure";
        RestartSec = "30";
        LoadCredential = [
          "claude-token:${config.age.secrets.vibe-kanban-claude-token.path}"
        ];

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
      };
    };

    systemd.services.oauth2-proxy = {
      after = [ "tailscale-online.service" ];
      requires = [ "tailscale-online.service" ];
    };

    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = "https://dex.mesh.gq";
      clientID = "vibe-kanban";
      clientSecretFile = config.age.secrets.dex-vibe-kanban-secret.path;
      scope = "openid email profile";
      redirectURL = "https://${cfg.host}/oauth2/callback";
      httpAddress = "http://127.0.0.1:${toString cfg.authPort}";
      upstream = [ "http://127.0.0.1:${toString cfg.port}" ];
      email.addresses = lib.concatStringsSep "\n" cfg.allowedEmails;
      reverseProxy = true;
      passBasicAuth = false;
      trustedProxyIP = [
        "127.0.0.1"
        "::1"
      ];
      cookie = {
        secure = true;
        secretFile = config.age.secrets.vibe-kanban-cookie-secret.path;
      };
      extraConfig = {
        skip-provider-button = true;
        cookie-samesite = "lax";
        flush-interval = "100ms";
      };
    };

    age.secrets.vibe-kanban-claude-token.file = ../../secrets/claude-oauth-token.age;
    age.secrets.dex-vibe-kanban-secret.file = ../../secrets/dex-vibe-kanban-secret.age;
    age.secrets.vibe-kanban-cookie-secret.file = ../../secrets/vibe-kanban-cookie-secret.age;

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
        # Task output and diffs stream over websockets and SSE.
        proxyWebsockets = true;
        extraConfig = tailnetOnly + ''
          proxy_buffering off;
          proxy_read_timeout 1d;
          client_max_body_size 0;
        '';
      };
    };
    security.acme.certs.${cfg.host}.server = "https://ca.mesh.gq/acme/acme/directory";
  };
}
