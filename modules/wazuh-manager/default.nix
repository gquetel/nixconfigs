{
  lib,
  config,
  nodes,
  pkgs,
  ...
}:
# Wazuh server (https://wazuh.com): manager, indexer and dashboard, the
# declarative equivalent of the upstream wazuh-docker single-node stack.
#
# People log in to the dashboard (https://wazuh.mesh.gq, tailnet only) through
# Dex. The service accounts between the containers use random passwords from
# agenix and a private CA that wazuh-setup makes once.
#
# Runs rootless, as modules/plane does: a dedicated `wazuh-manager` user owns
# the containers through home-manager's `services.podman` (Quadlet units under
# the user's systemd instance).
let
  cfg = config.wazuh-manager;

  user = "wazuh-manager";
  home = "/var/lib/wazuh-manager";
  # Certificates, generated configuration and env files. The home directory is
  # 0700, so the files in it can be 0644: the containers read them as UID 1000
  # of their own user namespace.
  stack = "${home}/stack";
  netName = "wazuh-net";
  domain = "wazuh.mesh.gq";
  dexUrl = "https://dex.mesh.gq";
  dashboardPort = 5601;

  # Version, image digests and config hash. packages/wazuh-agent/update.sh
  # writes this file, for the agents and the server together.
  pin = lib.importJSON ./image.json;
  inherit (pin) version;
  image = name: "docker.io/wazuh/wazuh-${name}:${version}@${pin.digests.${name}}";

  yaml = pkgs.formats.yaml { };

  # The upstream single-node ossec.conf, with the changes below. The image
  # copies /wazuh-config-mount over /var/ossec at each start, so this file is
  # the manager configuration.
  upstreamConf = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/wazuh/wazuh-docker/v${version}/single-node/config/wazuh_cluster/wazuh_manager.conf";
    hash = pin.configHash;
  };

  replacements = [
    # Enrollment needs the password in etc/authd.pass.
    [
      "<use_password>no</use_password>"
      "<use_password>yes</use_password>"
    ]
    # These three scan the container itself and only give false alerts.
    [
      "<sca>\n    <enabled>yes</enabled>"
      "<sca>\n    <enabled>no</enabled>"
    ]
    [
      "<rootcheck>\n    <disabled>no</disabled>"
      "<rootcheck>\n    <disabled>yes</disabled>"
    ]
    [
      "<syscheck>\n    <disabled>no</disabled>"
      "<syscheck>\n    <disabled>yes</disabled>"
    ]
  ];

  ossecConf = pkgs.runCommand "wazuh-manager-ossec.conf" { } ''
    substitute ${upstreamConf} $out ${
      lib.concatMapStringsSep " " (
        r: "--replace-fail ${lib.escapeShellArg (lib.elemAt r 0)} ${lib.escapeShellArg (lib.elemAt r 1)}"
      ) replacements
    }
  '';

  # Distinguished names of the private CA certificates, in RFC 2253 order.
  adminDn = "CN=admin,O=Wazuh";
  indexerDn = "CN=wazuh.indexer,O=Wazuh";
  indexerCerts = "/usr/share/wazuh-indexer/config/certs";
  securityDir = "/usr/share/wazuh-indexer/config/opensearch-security";

  indexerConf = yaml.generate "opensearch.yml" {
    "network.host" = "0.0.0.0";
    "node.name" = "wazuh.indexer";
    "cluster.name" = "wazuh-cluster";
    "path.data" = "/var/lib/wazuh-indexer";
    "path.logs" = "/var/log/wazuh-indexer";
    "discovery.type" = "single-node";
    "compatibility.override_main_response_version" = true;
    "plugins.security.ssl.http.enabled" = true;
    "plugins.security.ssl.http.pemcert_filepath" = "${indexerCerts}/indexer.pem";
    "plugins.security.ssl.http.pemkey_filepath" = "${indexerCerts}/indexer.key";
    "plugins.security.ssl.http.pemtrustedcas_filepath" = "${indexerCerts}/root-ca.pem";
    "plugins.security.ssl.transport.pemcert_filepath" = "${indexerCerts}/indexer.pem";
    "plugins.security.ssl.transport.pemkey_filepath" = "${indexerCerts}/indexer.key";
    "plugins.security.ssl.transport.pemtrustedcas_filepath" = "${indexerCerts}/root-ca.pem";
    "plugins.security.ssl.transport.enforce_hostname_verification" = false;
    "plugins.security.authcz.admin_dn" = [ adminDn ];
    "plugins.security.nodes_dn" = [ indexerDn ];
    "plugins.security.restapi.roles_enabled" = [
      "all_access"
      "security_rest_api_access"
    ];
    "plugins.security.system_indices.enabled" = true;
    "plugins.security.allow_default_init_securityindex" = true;
    "cluster.routing.allocation.disk.threshold_enabled" = false;
  };

  # Service accounts log in with a password (basic). People log in through
  # Dex (openid); the indexer checks the token that the dashboard forwards.
  securityConf = yaml.generate "config.yml" {
    _meta = {
      type = "config";
      config_version = 2;
    };
    config.dynamic = {
      http.anonymous_auth_enabled = false;
      authc = {
        basic_internal_auth_domain = {
          http_enabled = true;
          transport_enabled = true;
          order = 0;
          http_authenticator = {
            type = "basic";
            challenge = false;
          };
          authentication_backend.type = "intern";
        };
        openid_auth_domain = {
          http_enabled = true;
          transport_enabled = true;
          order = 1;
          http_authenticator = {
            type = "openid";
            challenge = false;
            config = {
              subject_key = "email";
              openid_connect_url = "${dexUrl}/.well-known/openid-configuration";
              openid_connect_idp = {
                enable_ssl = true;
                verify_hostnames = true;
                pemtrustedcas_filepath = "${indexerCerts}/step-ca.pem";
              };
            };
          };
          authentication_backend.type = "noop";
        };
      };
    };
  };

  # Only the listed Dex users get a role. Other Dex users can log in and see
  # nothing.
  rolesMapping = yaml.generate "roles_mapping.yml" {
    _meta = {
      type = "rolesmapping";
      config_version = 2;
    };
    all_access = {
      reserved = false;
      backend_roles = [ "admin" ];
      users = cfg.admins;
    };
    kibana_server = {
      reserved = true;
      users = [ "kibanaserver" ];
    };
    wazuh_ui_admin = {
      reserved = true;
      users = [ "kibanaserver" ] ++ cfg.admins;
    };
    manage_ism = {
      reserved = true;
      users = [ "kibanaserver" ];
    };
  };

  dashboardConf = yaml.generate "opensearch_dashboards.yml" {
    "server.host" = "0.0.0.0";
    "server.port" = dashboardPort;
    # TLS ends at the host nginx.
    "server.ssl.enabled" = false;
    "opensearch.hosts" = "https://wazuh.indexer:9200";
    "opensearch.ssl.verificationMode" = "full";
    "opensearch.ssl.certificateAuthorities" = [ "/usr/share/wazuh-dashboard/certs/root-ca.pem" ];
    "opensearch.requestHeadersWhitelist" = [
      "securitytenant"
      "Authorization"
    ];
    "opensearch_security.multitenancy.enabled" = false;
    "opensearch_security.readonly_mode.roles" = [ "kibana_read_only" ];
    "opensearch_security.cookie.secure" = true;
    "opensearch_security.auth.type" = "openid";
    "opensearch_security.openid.connect_url" = "${dexUrl}/.well-known/openid-configuration";
    "opensearch_security.openid.client_id" = "wazuh";
    # Expanded from the container environment (dashboard.env).
    "opensearch_security.openid.client_secret" = "\${OIDC_CLIENT_SECRET}";
    "opensearch_security.openid.scope" = "openid profile email";
    "opensearch_security.openid.base_redirect_url" = "https://${domain}";
    "opensearch_security.openid.root_ca" = "/usr/share/wazuh-dashboard/certs/step-ca.pem";
    "uiSettings.overrides.defaultRoute" = "/app/wz-home";
  };

  envFile = config.age.secrets."wazuh-server.env".path;

  # Makes the private CA and the files that hold secrets. Certificates are
  # made once; the other files at each start, from the agenix secrets.
  setup = pkgs.writeShellApplication {
    name = "wazuh-setup";
    runtimeInputs = [
      pkgs.apacheHttpd
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      umask 077
      mkdir -p ${stack}
      cd ${stack}
      set -a
      # shellcheck disable=SC1091
      . ${envFile}
      set +a

      if [ ! -f root-ca.pem ]; then
        openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
          -subj "/O=Wazuh/CN=wazuh-root-ca" -keyout root-ca.key -out root-ca.pem
      fi
      cert() {
        [ -f "$1.pem" ] && return
        openssl req -new -newkey rsa:3072 -nodes -subj "$2" -keyout "$1.key" -out "$1.csr"
        openssl x509 -req -in "$1.csr" -CA root-ca.pem -CAkey root-ca.key -CAcreateserial \
          -days 3650 -extfile <(printf 'subjectAltName=%s' "$3") -out "$1.pem"
        rm "$1.csr"
      }
      cert indexer "/O=Wazuh/CN=wazuh.indexer" "DNS:wazuh.indexer,DNS:localhost,IP:127.0.0.1"
      cert admin "/O=Wazuh/CN=admin" "DNS:admin"
      cert manager "/O=Wazuh/CN=wazuh.manager" "DNS:wazuh.manager"

      hash() { htpasswd -nbBC 12 "" "$1" | cut -d: -f2; }
      cat > internal_users.yml <<EOF
      _meta:
        type: internalusers
        config_version: 2
      admin:
        hash: "$(hash "$INDEXER_PASSWORD")"
        reserved: true
        backend_roles: [admin]
      kibanaserver:
        hash: "$(hash "$DASHBOARD_PASSWORD")"
        reserved: true
      EOF

      # run_as off: every dashboard user reaches the manager API as wazuh-wui.
      cat > wazuh.yml <<EOF
      hosts:
        - default:
            url: https://wazuh.manager
            port: 55000
            username: wazuh-wui
            password: "$API_PASSWORD"
            run_as: false
      EOF

      printf 'OIDC_CLIENT_SECRET=%s\n' "$(cat ${config.age.secrets.dex-wazuh-secret.path})" > dashboard.env

      chmod 0644 ./*.pem admin.key indexer.key manager.key internal_users.yml wazuh.yml
    '';
  };

  # Applies the security files (users, OIDC, role mapping) to the running
  # indexer. The indexer reads them itself only when it creates its security
  # index, on the first start. Waits up to 5 min for the indexer to answer.
  securityAdmin = pkgs.writeShellScript "wazuh-indexer-securityadmin" ''
    podman=${lib.getExe pkgs.podman}
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      $podman exec wazuh-indexer curl -sk -o /dev/null https://127.0.0.1:9200 && break
      ${pkgs.coreutils}/bin/sleep 5
    done
    exec $podman exec -e JAVA_HOME=/usr/share/wazuh-indexer/jdk wazuh-indexer \
      bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
      -cd ${securityDir} -icl -nhnv -h 127.0.0.1 \
      -cacert ${indexerCerts}/root-ca.pem -cert ${indexerCerts}/admin.pem -key ${indexerCerts}/admin.key
  '';

  network = [ "${netName}.network" ];
  hardening = [ "--security-opt=no-new-privileges" ];
  containerUnit = {
    Unit = {
      After = [ "wazuh-setup.service" ];
      Requires = [ "wazuh-setup.service" ];
    };
    # The start includes the image pull. Podman stops a pull in a systemd
    # unit after 5 min.
    Service.TimeoutStartSec = 300;
  };
  stepCa = ../step-ca/roots.pem;
in
{
  options.wazuh-manager = {
    enable = lib.mkEnableOption "Wazuh server (manager, indexer and dashboard)";

    admins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice@example.com" ];
      description = "E-mail addresses of the Dex users with full access to the dashboard.";
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
      # Must not overlap with the range of the plane user.
      subUidRanges = [
        {
          startUid = 165536;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 165536;
          count = 65536;
        }
      ];
    };

    # OpenSearch needs more memory map areas than the kernel default.
    boot.kernel.sysctl."vm.max_map_count" = 262144;
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${user} = {
      home.stateVersion = "25.05";

      # sd-switch waits until all the units that it starts are started, image
      # pulls included. It fails if this takes longer than this value (default
      # 2 min). The home-manager-wazuh-manager system unit stops after 5 min.
      systemd.user.servicesStartTimeoutMs = 300000;

      systemd.user.services.wazuh-setup = {
        Unit = {
          Description = "Wazuh server certificates and secret files";
          # A new secret is a new encrypted file. The unit then changes, runs
          # again, and restarts the containers that require it.
          X-Restart-Triggers = map (f: builtins.hashFile "sha256" f) [
            ../../secrets/wazuh-server.env.age
            ../../secrets/dex-wazuh-secret.age
            ../../secrets/wazuh-authd.pass.age
          ];
          # sd-switch stops and starts a changed unit by default. The stop also
          # stops the containers, and the start does not start them again.
          X-SwitchMethod = "restart";
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe setup;
        };
        Install.WantedBy = [ "default.target" ];
      };

      # Runs at each start of the indexer, after the container starts. Type
      # exec: the start is done when the script starts, thus sd-switch and the
      # dashboard do not wait until the indexer is ready.
      systemd.user.services.wazuh-indexer-security = {
        Unit = {
          Description = "Wazuh indexer security configuration";
          After = [ "podman-wazuh-indexer.service" ];
          BindsTo = [ "podman-wazuh-indexer.service" ];
        };
        Service = {
          Type = "exec";
          RemainAfterExit = true;
          ExecStart = "${securityAdmin}";
        };
        # default.target: a deploy starts the unit again after a failure.
        Install.WantedBy = [
          "podman-wazuh-indexer.service"
          "default.target"
        ];
      };

      services.podman = {
        enable = true;
        networks.${netName} = { };

        containers.wazuh-manager = {
          image = image "manager";
          inherit network;
          networkAlias = [ "wazuh.manager" ];
          # Published on all addresses: a user unit cannot wait for the
          # tailscale IP. The host firewall keeps both ports closed, except on
          # the trusted tailscale0 interface.
          # 1514: agent events (remoted). 1515: enrollment (authd).
          ports = [
            "1514:1514"
            "1515:1515"
          ];
          environment = {
            INDEXER_URL = "https://wazuh.indexer:9200";
            INDEXER_USERNAME = "admin";
            FILEBEAT_SSL_VERIFICATION_MODE = "full";
            SSL_CERTIFICATE_AUTHORITIES = "/etc/ssl/root-ca.pem";
            SSL_CERTIFICATE = "/etc/ssl/filebeat.pem";
            SSL_KEY = "/etc/ssl/filebeat.key";
            API_USERNAME = "wazuh-wui";
          };
          # INDEXER_PASSWORD, API_PASSWORD.
          environmentFile = [ envFile ];
          # Volume list from the upstream single-node compose file.
          volumes = [
            "api_configuration:/var/ossec/api/configuration"
            "etc:/var/ossec/etc"
            "logs:/var/ossec/logs"
            "queue:/var/ossec/queue"
            "var_multigroups:/var/ossec/var/multigroups"
            "integrations:/var/ossec/integrations"
            "active_response:/var/ossec/active-response/bin"
            "agentless:/var/ossec/agentless"
            "wodles:/var/ossec/wodles"
            "filebeat_etc:/etc/filebeat"
            "filebeat_var:/var/lib/filebeat"
            "${stack}/root-ca.pem:/etc/ssl/root-ca.pem:ro"
            "${stack}/manager.pem:/etc/ssl/filebeat.pem:ro"
            "${stack}/manager.key:/etc/ssl/filebeat.key:ro"
            "${ossecConf}:/wazuh-config-mount/etc/ossec.conf:ro"
            "${config.age.secrets."wazuh-authd.pass".path}:/wazuh-config-mount/etc/authd.pass:ro"
          ];
          extraPodmanArgs = hardening ++ [
            # The manager names its queue/indexer/ folders and its own agent
            # (000) after the hostname. Podman gives a new random one at each
            # start, which leaves a new set of folders each time.
            "--hostname=wazuh-manager"
          ];
          extraConfig = containerUnit;
        };

        containers.wazuh-indexer = {
          image = image "indexer";
          inherit network;
          networkAlias = [ "wazuh.indexer" ];
          environment.OPENSEARCH_JAVA_OPTS = "-Xms1g -Xmx1g";
          volumes = [
            "indexer_data:/var/lib/wazuh-indexer"
            "${indexerConf}:/usr/share/wazuh-indexer/config/opensearch.yml:ro"
            "${stack}/root-ca.pem:${indexerCerts}/root-ca.pem:ro"
            "${stack}/indexer.pem:${indexerCerts}/indexer.pem:ro"
            "${stack}/indexer.key:${indexerCerts}/indexer.key:ro"
            "${stack}/admin.pem:${indexerCerts}/admin.pem:ro"
            "${stack}/admin.key:${indexerCerts}/admin.key:ro"
            "${stepCa}:${indexerCerts}/step-ca.pem:ro"
            "${securityConf}:${securityDir}/config.yml:ro"
            "${rolesMapping}:${securityDir}/roles_mapping.yml:ro"
            "${stack}/internal_users.yml:${securityDir}/internal_users.yml:ro"
          ];
          extraPodmanArgs = hardening;
          extraConfig = containerUnit;
        };

        containers.wazuh-dashboard = {
          image = image "dashboard";
          inherit network;
          networkAlias = [ "wazuh.dashboard" ];
          ports = [ "127.0.0.1:${toString dashboardPort}:${toString dashboardPort}" ];
          environment = {
            INDEXER_USERNAME = "admin";
            DASHBOARD_USERNAME = "kibanaserver";
            WAZUH_API_URL = "https://wazuh.manager";
            API_USERNAME = "wazuh-wui";
          };
          # INDEXER_PASSWORD, DASHBOARD_PASSWORD, API_PASSWORD; OIDC_CLIENT_SECRET.
          environmentFile = [
            envFile
            "${stack}/dashboard.env"
          ];
          volumes = [
            "dashboard_config:/usr/share/wazuh-dashboard/data/wazuh/config"
            "dashboard_custom:/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom"
            "${dashboardConf}:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml:ro"
            "${stack}/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml"
            "${stack}/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem:ro"
            "${stepCa}:/usr/share/wazuh-dashboard/certs/step-ca.pem:ro"
          ];
          extraPodmanArgs = hardening;
          extraConfig = lib.recursiveUpdate containerUnit {
            Unit = {
              After = [ "podman-wazuh-indexer.service" ];
              Wants = [ "podman-wazuh-indexer.service" ];
            };
          };
        };
      };
    };

    services.nginx.virtualHosts.${domain} = {
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
        proxyPass = "http://127.0.0.1:${toString dashboardPort}";
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
          # The OpenID session cookies are larger than the default buffers.
          proxy_buffer_size 16k;
          proxy_buffers 8 16k;
        '';
      };
    };
    security.acme.certs.${domain}.server = "https://ca.mesh.gq/acme/acme/directory";

    age.secrets = {
      "wazuh-authd.pass" = {
        file = ../../secrets/wazuh-authd.pass.age;
        owner = user;
        group = user;
      };
      # INDEXER_PASSWORD, DASHBOARD_PASSWORD and API_PASSWORD, one KEY=VALUE
      # line each.
      "wazuh-server.env" = {
        file = ../../secrets/wazuh-server.env.age;
        owner = user;
        group = user;
      };
      dex-wazuh-secret = {
        file = ../../secrets/dex-wazuh-secret.age;
        owner = user;
        group = user;
      };
    };
  };
}
