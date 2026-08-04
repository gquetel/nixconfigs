{
  lib,
  config,
  pkgs,
  ...
}:
# OpenHands Agent Canvas, following upstream's SELF_HOSTING.md.
#
# The agent reads and writes the filesystem, runs shell commands and reaches
# the network as the service user, so reaching the UI means code execution as
# that user. nginx (tailnet-only) + oauth2-proxy (dex) gate access before the
# loopback ingress port.
let
  cfg = config.openhands;

  agent-canvas = pkgs.callPackage ../../packages/openhands-agent-canvas { };

  userCfg = config.users.users.${cfg.user};
  homeDir = userCfg.home;

  # PATH for the launcher and every command the agent runs.
  runtimePath = with pkgs; [
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

  tailnetOnly = ''
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';
in
{
  options.openhands = with lib; {
    enable = mkEnableOption "OpenHands Agent Canvas";

    user = mkOption {
      type = types.str;
      default = "gquetel";
      description = ''
        Login user the stack and its agents run as. Reaching the ingress is a
        shell as this user; the tailnet ACL and oauth2-proxy limit that.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "canvas.mesh.gq";
      description = "Tailnet-internal hostname serving the UI.";
    };

    port = mkOption {
      type = types.port;
      default = 9910;
      description = ''
        Loopback port of the ingress proxy, the only one nginx talks to. It
        routes /api/* and /sockets to the backends and everything else to the
        frontend.
      '';
    };

    backendPort = mkOption {
      type = types.port;
      default = 9913;
      description = ''
        Loopback port for the agent server. Its VSCode service claims this
        port plus 1000.
      '';
    };

    automationPort = mkOption {
      type = types.port;
      default = 9914;
      description = "Loopback port for the automation backend.";
    };

    staticPort = mkOption {
      type = types.port;
      default = 9915;
      description = "Loopback port serving the pre-built frontend assets.";
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

    systemd.services.openhands = {
      description = "OpenHands Agent Canvas";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = runtimePath;

      environment = {
        # Every service binds loopback; only the ingress port is fronted.
        OH_CANVAS_SAFE_BACKEND_PORT = toString cfg.backendPort;
        OH_CANVAS_SAFE_AUTOMATION_PORT = toString cfg.automationPort;
        OH_CANVAS_SAFE_VITE_PORT = toString cfg.staticPort;
        # State lives under $HOME/.openhands: the session API key, the settings
        # encryption key, conversations and the automation database.
        HOME = homeDir;
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };

      serviceConfig = {
        # uvx fetches the Python halves of the stack (agent server, automation)
        # on first start, at the versions pinned by the npm package, and caches
        # them under $HOME/.cache/uv.
        ExecStart = "${lib.getExe agent-canvas} --port ${toString cfg.port}";
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
      clientID = "openhands";
      clientSecretFile = config.age.secrets.dex-openhands-secret.path;
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
        secretFile = config.age.secrets.openhands-cookie-secret.path;
      };
      extraConfig = {
        skip-provider-button = true;
        cookie-samesite = "lax";
        flush-interval = "100ms";
      };
    };

    age.secrets.dex-openhands-secret.file = ../../secrets/dex-openhands-secret.age;
    age.secrets.openhands-cookie-secret.file = ../../secrets/openhands-cookie-secret.age;

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
        # Agent events stream over websockets.
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
