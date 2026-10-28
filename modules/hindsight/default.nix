{
  lib,
  config,
  pkgs,
  ...
}:
# Self-hosted Hindsight (https://hindsight.vectorize.io): shared agent memory
# for Hermes, Claude Code and Codex.
#
# Runs rootless, like the Plane module: a dedicated `hindsight` system user
# owns the API and its pgvector Postgres through home-manager's
# `services.podman`. The API is published on loopback and the host nginx
# exposes it to the tailnet only. API clients send `Authorization: Bearer <key>`.
#
# The Control Plane (web UI) holds the API key and has no login of its own, so
# it is not published. Only an oauth2-proxy (Dex login) on the same podman
# network can reach it, and only that proxy is published on loopback.
let
  cfg = config.hindsight;

  user = "hindsight";
  home = "/var/lib/hindsight";
  netName = "hindsight-net";

  # Images pinned by digest. Re-resolve with
  # `skopeo inspect --format '{{.Digest}}' docker://<ref>` when bumping.
  images = {
    # The full image: local embedding and reranker models are baked in.
    api = "ghcr.io/vectorize-io/hindsight-api:1.1.0@sha256:cdfeb26e92ad33d54a8a7e4cfe6e67b55d619f25ea5f5bba0a3281d701a82b36";
    ui = "ghcr.io/vectorize-io/hindsight-control-plane:1.1.0@sha256:373f86848649a8dadc9b2d9ecf1d18b4c446162ca7b556fc4152e92ef433e983";
    db = "docker.io/pgvector/pgvector:0.8.1-pg17@sha256:3e8b3adfd27b5707128f60956f62a793c3c9326ea8cfaf0eab7adccb5d700b21";
    oauth2Proxy = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.5@sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916";
  };

  # POSTGRES_PASSWORD, HINDSIGHT_API_DATABASE_URL, the LLM endpoint and the
  # client API key. See secrets/secrets.nix for the expected keys.
  envFile = config.age.secrets."hindsight.env".path;
  # The API key only, so that the UI does not get the database and LLM
  # credentials.
  uiEnvFile = config.age.secrets."hindsight-cp.env".path;
  # The Dex client secret and the cookie secret of the proxy.
  proxyEnvFile = config.age.secrets."hindsight-oauth2-proxy.env".path;

  allowedEmails = pkgs.writeText "hindsight-allowed-emails" (lib.concatLines cfg.ui.allowedEmails);

  network = [ "${netName}.network" ];
  hardening = [ "--security-opt=no-new-privileges" ];

  # Host CA bundle, which includes the step-ca root, so that containers can
  # reach mesh.gq endpoints: the LLM for the API, Dex for the proxy.
  caBundle = "/etc/ssl/certs/ca-certificates.crt";

  # glibc address-selection table that prefers IPv6. The container only has a
  # ULA IPv6 address, so the default table tries IPv4 first; an endpoint whose
  # IPv4 does not answer then costs ~130s per connection. Same as the glibc
  # default, except that fc00::/7 shares the label of ::/0.
  gaiConf = pkgs.writeText "gai.conf" ''
    label ::1/128 0
    label ::/0 1
    label 2002::/16 2
    label ::/96 3
    label ::ffff:0:0/96 4
    label fec0::/10 5
    label fc00::/7 1
    label 2001:0::/32 7
  '';

  containers = {
    hindsight-db = {
      image = images.db;
      environment = {
        POSTGRES_USER = "hindsight";
        POSTGRES_DB = "hindsight";
        PGDATA = "/var/lib/postgresql/data";
      };
      environmentFile = [ envFile ];
      volumes = [ "pgdata:/var/lib/postgresql/data" ];
      inherit network;
      extraPodmanArgs = hardening;
    };

    hindsight-api = {
      image = images.api;
      environment = {
        HINDSIGHT_API_VECTOR_EXTENSION = "pgvector";
        # Any OpenAI-compatible endpoint. HINDSIGHT_API_LLM_BASE_URL,
        # HINDSIGHT_API_LLM_MODEL and HINDSIGHT_API_LLM_API_KEY come from the
        # env file.
        HINDSIGHT_API_LLM_PROVIDER = "openai";
        # The endpoint queues parallel requests: more of them only make each
        # one wait past the timeout, and each timeout causes a retry.
        HINDSIGHT_API_LLM_MAX_CONCURRENT = "2";
        HINDSIGHT_API_LLM_TIMEOUT = "300";
        HINDSIGHT_API_EMBEDDINGS_PROVIDER = "local";
        HINDSIGHT_API_RERANKER_PROVIDER = "local";
        HINDSIGHT_API_TENANT_EXTENSION = "hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension";
        HINDSIGHT_API_WORKER_ID = "vapula";
        SSL_CERT_FILE = caBundle;
        REQUESTS_CA_BUNDLE = caBundle;
      };
      environmentFile = [ envFile ];
      volumes = [
        "${caBundle}:${caBundle}:ro"
        "${gaiConf}:/etc/gai.conf:ro"
      ];
      ports = [ "127.0.0.1:${toString cfg.port}:8888" ];
      inherit network;
      extraPodmanArgs = hardening;
      extraConfig.Unit = {
        After = [ "podman-hindsight-db.service" ];
        Wants = [ "podman-hindsight-db.service" ];
      };
    };

    hindsight-control-plane = {
      image = images.ui;
      environment.HINDSIGHT_CP_DATAPLANE_API_URL = "http://hindsight-api:8888";
      environmentFile = [ uiEnvFile ];
      inherit network;
      extraPodmanArgs = hardening;
      extraConfig.Unit = {
        After = [ "podman-hindsight-api.service" ];
        Wants = [ "podman-hindsight-api.service" ];
      };
    };

    hindsight-oauth2-proxy = {
      image = images.oauth2Proxy;
      environment = {
        OAUTH2_PROXY_PROVIDER = "oidc";
        OAUTH2_PROXY_OIDC_ISSUER_URL = "https://dex.mesh.gq";
        OAUTH2_PROXY_CLIENT_ID = "hindsight";
        OAUTH2_PROXY_SCOPE = "openid email profile";
        OAUTH2_PROXY_REDIRECT_URL = "https://${cfg.ui.host}/oauth2/callback";
        OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE = "/etc/oauth2-proxy/emails";
        OAUTH2_PROXY_HTTP_ADDRESS = "0.0.0.0:4180";
        OAUTH2_PROXY_UPSTREAMS = "http://hindsight-control-plane:9999";
        OAUTH2_PROXY_REVERSE_PROXY = "true";
        OAUTH2_PROXY_SKIP_PROVIDER_BUTTON = "true";
        SSL_CERT_FILE = caBundle;
      };
      environmentFile = [ proxyEnvFile ];
      volumes = [
        "${caBundle}:${caBundle}:ro"
        "${allowedEmails}:/etc/oauth2-proxy/emails:ro"
      ];
      ports = [ "127.0.0.1:${toString cfg.ui.port}:4180" ];
      inherit network;
      extraPodmanArgs = hardening;
      extraConfig.Unit = {
        After = [ "podman-hindsight-control-plane.service" ];
        Wants = [ "podman-hindsight-control-plane.service" ];
      };
    };
  };
in
{
  options.hindsight = with lib; {
    enable = mkEnableOption "self-hosted Hindsight agent memory";

    host = mkOption {
      type = types.str;
      default = "hindsight.mesh.gq";
      description = "Tailnet-internal hostname serving the API.";
    };

    port = mkOption {
      type = types.port;
      default = 8888;
      description = "Loopback port the API container is published on.";
    };

    ui.host = mkOption {
      type = types.str;
      default = "hindsight-ui.mesh.gq";
      description = "Tailnet-internal hostname serving the Control Plane.";
    };

    ui.port = mkOption {
      type = types.port;
      default = 9999;
      description = "Loopback port the Control Plane's oauth2-proxy is published on.";
    };

    ui.allowedEmails = mkOption {
      type = types.listOf types.str;
      default = [ "gquetel@mail.foo.gq" ];
      description = "Dex identities allowed to reach the Control Plane.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      inherit home;
      createHome = true;
      linger = true;
      subUidRanges = [
        {
          startUid = 231072;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 231072;
          count = 65536;
        }
      ];
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${user} = {
      home.stateVersion = "25.05";
      services.podman = {
        enable = true;
        # IPv6 egress: the LLM endpoint may answer on IPv6 only.
        networks.${netName}.extraConfig.Network.IPv6 = true;
        inherit containers;
      };
    };

    tailnet.vhosts.${cfg.host} = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
      extraConfig = ''
        # Session transcripts are sent whole on retain.
        client_max_body_size 50m;
        # Reflect calls wait on the LLM.
        proxy_read_timeout 10m;
      '';
    };

    tailnet.vhosts.${cfg.ui.host} = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString cfg.ui.port}";
    };

    age.secrets."hindsight.env" = {
      file = ../../secrets/hindsight.env.age;
      owner = user;
      group = user;
    };

    age.secrets."hindsight-cp.env" = {
      file = ../../secrets/hindsight-cp.env.age;
      owner = user;
      group = user;
    };

    age.secrets."hindsight-oauth2-proxy.env" = {
      file = ../../secrets/hindsight-oauth2-proxy.env.age;
      owner = user;
      group = user;
    };
  };
}
