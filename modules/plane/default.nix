{
  lib,
  config,
  nodes,
  pkgs,
  ...
}:
# Self-hosted Plane (https://plane.so), the declarative equivalent of the
# upstream community docker-compose stack.
#
# Runs *rootless*: a dedicated unprivileged `plane` system user owns the whole
# stack via home-manager's `services.podman` (Quadlet units under the user's
# systemd instance). No root daemon, no oci-containers. The host nginx (running
# rootful) fronts the rootless proxy container published on 127.0.0.1.
let
  cfg = config.plane;

  user = "plane";
  home = "/var/lib/plane";
  netName = "plane-net";

  release = "v1.3.1";

  # Images pinned by digest. Re-resolve using docker buildx imagetools inspect <ref>
  # whenever the release is bumped.
  # Note: podman resolves using the hash and not the release version.
  images = {
    backend = "docker.io/makeplane/plane-backend:${release}@sha256:2cdcb5f778c6ccacebce0e5a751d39fac4a549a44e049a5b110a7623cfdad139";
    frontend = "docker.io/makeplane/plane-frontend:${release}@sha256:c178fd85c4588165262cfe748bd103fdeccebbbab827c53e71b9ce32fff84f86";
    space = "docker.io/makeplane/plane-space:${release}@sha256:e08c2c8741ae6f81a9326dc9201e7e09c0c411b87a20198f9ea9e5cf2fae3488";
    admin = "docker.io/makeplane/plane-admin:${release}@sha256:ff9219127a2c2c4a4bb066d6a0e25a5fc6a11204cf8484b521dada53d696fe43";
    live = "docker.io/makeplane/plane-live:${release}@sha256:2073b6950a394545ea1db6ed4157e951ad5a6e1881e74f4f9238ace6c35bbf3d";
    proxy = "docker.io/makeplane/plane-proxy:${release}@sha256:b4f8bb6998052dcd1488171a90d473674cefbc6ec77114d5095b48c805f4ad27";
    postgres = "docker.io/library/postgres:15.7-alpine@sha256:468d34fefd6338031787c7b8e94078975b3aaf4d66c7ead25c39cd3ba46a15c6";
    valkey = "docker.io/valkey/valkey:7.2.11-alpine@sha256:10328d00120dc14fbc87b2ed61b7677ddbb0d011e705361b4788329a0ec69a93";
    rabbitmq = "docker.io/library/rabbitmq:3.13.6-management-alpine@sha256:611107e29cce05c2acd968325d5dcbde7e2fee404970f1ead75fdb22be2821b3";
    minio = "docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e";
  };
  backend = images.backend;
  domain = "plane.mesh.gq";

  proxyPort = 3333;
  # One env file for every container.
  # TODO: Split it across every container.
  envFile = config.age.secrets."plane.env".path;

  dbEnv = {
    PGHOST = "plane-db";
    PGDATABASE = "plane";
    POSTGRES_USER = "plane";
    POSTGRES_DB = "plane";
    POSTGRES_PORT = "5432";
    PGDATA = "/var/lib/postgresql/data";
  };

  redisHost = "plane-redis";
  redisPort = "16379";
  redisEnv = {
    REDIS_HOST = redisHost;
    REDIS_PORT = redisPort;
    REDIS_URL = "redis://${redisHost}:${redisPort}/";
  };

  mqEnv = {
    RABBITMQ_HOST = "plane-mq";
    RABBITMQ_PORT = "5672";
    RABBITMQ_DEFAULT_USER = "plane";
    RABBITMQ_DEFAULT_VHOST = "plane";
    RABBITMQ_VHOST = "plane";
  };

  s3Env = {
    AWS_REGION = "";
    AWS_S3_ENDPOINT_URL = "http://plane-minio:9000";
    AWS_S3_BUCKET_NAME = "uploads";
  };

  # This is the conf for the shipped caddy. It is kept as the proxy, but TLS is
  # delegated to the host nginx.
  proxyEnv = {
    APP_DOMAIN = domain;
    FILE_SIZE_LIMIT = "5242880";
    BUCKET_NAME = "uploads";
    LISTEN_HTTP_PORT = "80";
    LISTEN_HTTPS_PORT = "443";
    SITE_ADDRESS = ":80";
  };

  appEnv = {
    WEB_URL = "https://${domain}";
    DEBUG = "0";
    CORS_ALLOWED_ORIGINS = "https://${domain}";
    GUNICORN_WORKERS = "1";
    USE_MINIO = "1";
    API_KEY_RATE_LIMIT = "60/minute";
    MINIO_ENDPOINT_SSL = "0";
    WEBHOOK_ALLOWED_IPS = "";
    WEBHOOK_ALLOWED_HOSTS = "";
  };

  # Full env for the python/backend tier (api, worker, beat-worker, migrator):
  backendEnv = appEnv // dbEnv // redisEnv // s3Env // proxyEnv;

  network = [ "${netName}.network" ];
  hardening = [ "--security-opt=no-new-privileges" ];
  # We try to restrict the read-write capabilities of containers. We apply read-only,
  # only to the stateless app containers. One can check if an app requires write access
  # by checking the journal: journalctl --user -u podman-<name>
  # If it only target some dirs, we can add a tmpfs for the path, else we can remove it
  # from this set.
  readonlyRootfs = [ "--read-only" ];
  # The frontend images (web/space/admin) serve the built app via nginx, which
  # must create temp dirs under /var/cache/nginx at startup. Keep the root FS
  # read-only but give nginx that one writable path.
  frontendRO = readonlyRootfs ++ [ "--tmpfs=/var/cache/nginx" ];

  depUnits = names: map (n: "podman-${n}.service") names;
  afterCfg =
    names:
    lib.optionalAttrs (names != [ ]) {
      Unit = {
        After = depUnits names;
        Wants = depUnits names;
      };
    };

  mkBackendC =
    {
      exec,
      logVol,
      alias ? null,
      deps ? [ ],
      service ? { },
    }:
    {
      image = backend;
      inherit exec network;
      environment = backendEnv;
      environmentFile = [ envFile ];
      volumes = [ "${logVol}:/code/plane/logs" ];
      networkAlias = lib.optionals (alias != null) [ alias ];
      # TODO, try addind readonlyrootfs ?
      extraPodmanArgs = hardening;
      extraConfig = (afterCfg deps) // (lib.optionalAttrs (service != { }) { Service = service; });
    };

  containers = {
    plane-db = {
      image = images.postgres;
      exec = "postgres -c max_connections=1000";
      environment = dbEnv;
      environmentFile = [ envFile ];
      volumes = [ "pgdata:/var/lib/postgresql/data" ];
      inherit network;
      extraPodmanArgs = hardening;
    };

    plane-redis = {
      image = images.valkey;
      exec = "valkey-server --port ${redisPort}";
      volumes = [ "redisdata:/data" ];
      inherit network;
      extraPodmanArgs = hardening;
    };

    plane-mq = {
      image = images.rabbitmq;
      environment = mqEnv;
      environmentFile = [ envFile ];
      volumes = [ "rabbitmq_data:/var/lib/rabbitmq" ];
      inherit network;
      extraPodmanArgs = hardening;
    };

    plane-minio = {
      image = images.minio;
      exec = "server /export --console-address :9090";
      # MINIO_ROOT_USER / MINIO_ROOT_PASSWORD come from the env file.
      environmentFile = [ envFile ];
      volumes = [ "uploads:/export" ];
      inherit network;
      extraPodmanArgs = hardening;
    };

    plane-api = mkBackendC {
      exec = "./bin/docker-entrypoint-api.sh";
      logVol = "logs_api";
      alias = "api";
      deps = [
        "plane-db"
        "plane-redis"
        "plane-mq"
      ];
    };

    plane-worker = mkBackendC {
      exec = "./bin/docker-entrypoint-worker.sh";
      logVol = "logs_worker";
      deps = [
        "plane-api"
        "plane-db"
        "plane-redis"
        "plane-mq"
      ];
    };

    plane-beat-worker = mkBackendC {
      exec = "./bin/docker-entrypoint-beat.sh";
      logVol = "logs_beat-worker";
      deps = [
        "plane-api"
        "plane-db"
        "plane-redis"
        "plane-mq"
      ];
    };

    plane-migrator = mkBackendC {
      exec = "./bin/docker-entrypoint-migrator.sh";
      logVol = "logs_migrator";
      deps = [
        "plane-db"
        "plane-redis"
      ];
      service.Restart = "no";
    };

    plane-web = {
      image = images.frontend;
      inherit network;
      networkAlias = [ "web" ];
      extraPodmanArgs = hardening ++ frontendRO;
      extraConfig = afterCfg [ "plane-api" ];
    };

    plane-space = {
      image = images.space;
      inherit network;
      networkAlias = [ "space" ];
      extraPodmanArgs = hardening ++ frontendRO;
      extraConfig = afterCfg [
        "plane-api"
        "plane-web"
      ];
    };

    plane-admin = {
      image = images.admin;
      inherit network;
      networkAlias = [ "admin" ];
      extraPodmanArgs = hardening ++ frontendRO;
      extraConfig = afterCfg [
        "plane-api"
        "plane-web"
      ];
    };

    plane-live = {
      image = images.live;
      environment = {
        API_BASE_URL = "http://api:8000";
      }
      // redisEnv;
      # LIVE_SERVER_SECRET_KEY from the env file.
      environmentFile = [ envFile ];
      inherit network;
      networkAlias = [ "live" ];
      extraPodmanArgs = hardening ++ readonlyRootfs;
      extraConfig = afterCfg [
        "plane-api"
        "plane-web"
      ];
    };

    # Caddy ships as the reverse proxy in the upstream compose; we keep it only
    # for its internal path routing (TLS is nginx's job) and publish it on
    # loopback for the host nginx to proxy.
    plane-proxy = {
      image = images.proxy;
      environment = proxyEnv;
      environmentFile = [ envFile ];
      ports = [ "127.0.0.1:${toString proxyPort}:80" ];
      inherit network;
      extraPodmanArgs =
        hardening
        ++ readonlyRootfs
        # Caddy save its local CA / autosave to /data and /config
        ++ [
          "--tmpfs=/data"
          "--tmpfs=/config"
        ];
      extraConfig = afterCfg [
        "plane-web"
        "plane-api"
        "plane-space"
        "plane-admin"
        "plane-live"
      ];
    };
  };
in
{
  options.plane = {
    enable = lib.mkEnableOption "self-hosted Plane project management";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = home;
      createHome = true;
      linger = true;
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
    };

    # We want rootless pods, so we create a dedicated user to run its own systemd units.
    # We rely on home-manager.user.<user>.services.podman for that: we have a rootless
    # setup.
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${user} = {
      home.stateVersion = "25.05";
      services.podman = {
        enable = true;
        networks.${netName} = { };
        inherit containers;
      };
    };

    services.nginx.virtualHosts."${domain}" = {
      forceSSL = true;
      enableACME = true;
      listen = [
        {
          addr = nodes.garmr.config.machine.meta.ipTailscale;
          port = 443;
          ssl = true;
        }
        {
          addr = nodes.garmr.config.machine.meta.ipTailscale;
          port = 80;
        }
      ];
      locations."/" = {
        recommendedProxySettings = true;
        # Plane's live collaboration server uses websockets.
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 20m;
          allow 100.64.0.0/10;
          allow  fd7a:115c:a1e0::/48;
          deny all;'';
        proxyPass = "http://127.0.0.1:${toString proxyPort}";
      };
    };
    security.acme.certs."${domain}".server = "https://ca.mesh.gq/acme/acme/directory";

    age.secrets."plane.env" = {
      file = ../../secrets/plane.env.age;
      owner = user;
      group = user;
    };
  };
}
