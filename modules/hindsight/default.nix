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
# exposes it to the tailnet only. Clients send `Authorization: Bearer <key>`.
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
    db = "docker.io/pgvector/pgvector:0.8.1-pg17@sha256:3e8b3adfd27b5707128f60956f62a793c3c9326ea8cfaf0eab7adccb5d700b21";
  };

  # POSTGRES_PASSWORD, HINDSIGHT_API_DATABASE_URL, the LLM endpoint and the
  # client API key. See secrets/secrets.nix for the expected keys.
  envFile = config.age.secrets."hindsight.env".path;

  network = [ "${netName}.network" ];
  hardening = [ "--security-opt=no-new-privileges" ];

  # Host CA bundle, which includes the step-ca root, so that the API can
  # reach an LLM endpoint with a mesh.gq certificate.
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

    age.secrets."hindsight.env" = {
      file = ../../secrets/hindsight.env.age;
      owner = user;
      group = user;
    };
  };
}
