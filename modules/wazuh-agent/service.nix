{
  config,
  lib,
  pkgs,
  ...
}:
# Generic Wazuh agent service, independent of this cluster.
let
  cfg = config.services.wazuh-agent;

  settingsFormat = pkgs.formats.xml { withHeader = false; };
  configFile = settingsFormat.generate "ossec.conf" { ossec_config = cfg.settings; };

  # Wazuh finds its home from the path of its own binary (bin/..). Each daemon
  # sees the state directory at /var/ossec, with the package trees and the
  # generated configuration mounted read-only on top.
  home = "/var/ossec";
  stateDir = "/var/lib/wazuh-agent";

  daemons = [
    "wazuh-agentd"
    "wazuh-logcollector"
    "wazuh-syscheckd"
    "wazuh-modulesd"
  ];

  mounts = {
    BindPaths = [ "${stateDir}:${home}" ];
    BindReadOnlyPaths = [
      "${cfg.package}/bin:${home}/bin"
      "${cfg.package}/lib:${home}/lib"
      "${cfg.package}/ruleset:${home}/ruleset"
      "${cfg.package}/wodles:${home}/wodles"
      "${cfg.package}/etc/internal_options.conf:${home}/etc/internal_options.conf"
      "${configFile}:${home}/etc/ossec.conf"
    ];
  };

  hardening = {
    ProtectSystem = "strict";
    # File integrity monitoring and log collection read /root and /home.
    ProtectHome = "read-only";
    PrivateTmp = true;
    NoNewPrivileges = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
  };

  # Creates the state tree from the package skeleton. Existing state (keys,
  # queues, logs) is kept. Directories that a new version adds are created.
  setup = pkgs.writeShellScript "wazuh-agent-setup" ''
    set -eu
    for dir in etc logs queue tmp var; do
      cp -rn --no-preserve=ownership ${cfg.package}/$dir ${stateDir}/
    done
    chmod -R u+w ${stateDir}
    chown -R ${cfg.user}:${cfg.group} ${stateDir}
    chown root:${cfg.group} ${stateDir}
    chmod 0750 ${stateDir}
    ${lib.optionalString (cfg.enrollment.passwordFile != null) ''
      install -m 0640 -o root -g ${cfg.group} \
        "$CREDENTIALS_DIRECTORY/password" ${stateDir}/etc/authd.pass
    ''}
  '';
in
{
  options.services.wazuh-agent = {
    enable = lib.mkEnableOption "the Wazuh agent";

    package = lib.mkPackageOption pkgs "wazuh-agent" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "wazuh";
      description = ''
        User that wazuh-agentd changes to after start. The other daemons run
        as root, as upstream does. The name is fixed in the agent binaries.
      '';
      readOnly = true;
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "wazuh";
      description = "Group of the agent state files.";
      readOnly = true;
    };

    manager = {
      address = lib.mkOption {
        type = lib.types.str;
        example = "wazuh.example.com";
        description = "Address of the Wazuh manager.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1514;
        description = "Port of the manager for agent events (wazuh-remoted).";
      };
    };

    enrollment = {
      agentName = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "Name of the agent on the manager.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1515;
        description = "Port of the manager for enrollment (wazuh-authd).";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/wazuh-authd.pass";
        description = ''
          File that holds the enrollment password of the manager. Use a path
          outside the Nix store.
        '';
      };
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      description = ''
        Content of the `<ossec_config>` element of ossec.conf. Attributes
        start with `@`. A list makes repeated elements. See
        <https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/>.
      '';
      example = lib.literalExpression ''
        {
          localfile = [
            {
              log_format = "audit";
              location = "/var/log/audit/audit.log";
            }
          ];
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Scalars are defaults. Lists are normal definitions, so that a host adds
    # to them (for example one more localfile) and does not replace them.
    services.wazuh-agent.settings =
      lib.mapAttrsRecursive (_: v: if lib.isList v then v else lib.mkDefault v)
        {
          client = {
            server = {
              inherit (cfg.manager) address port;
              protocol = "tcp";
            };
            enrollment = {
              enabled = "yes";
              agent_name = cfg.enrollment.agentName;
              port = cfg.enrollment.port;
            };
            # With "yes", the agent restarts itself through wazuh-control, outside
            # of systemd.
            auto_restart = "no";
            crypto_method = "aes";
          };
          client_buffer = {
            disabled = "no";
            queue_size = 5000;
            events_per_second = 500;
          };
          logging.log_format = "plain";
          active-response.disabled = "yes";
          sca.enabled = "no";
          rootcheck = {
            disabled = "no";
            frequency = 43200;
            rootkit_files = "etc/shared/rootkit_files.txt";
            rootkit_trojans = "etc/shared/rootkit_trojans.txt";
            skip_nfs = "yes";
          };
          # On NixOS most of /etc links into the store, and syscheck does not
          # follow links. It watches the real files: passwd, shadow, sudoers,
          # SSH host keys.
          syscheck = {
            disabled = "no";
            frequency = 43200;
            scan_on_start = "yes";
            directories = "/etc,/boot";
            ignore = [
              "/etc/mtab"
              "/etc/resolv.conf"
              "/etc/adjtime"
              "/etc/.clean"
            ];
            skip_nfs = "yes";
            skip_dev = "yes";
            skip_proc = "yes";
            skip_sys = "yes";
          };
          wodle = [
            {
              "@name" = "syscollector";
              disabled = "no";
              interval = "1h";
              scan_on_start = "yes";
              hardware = "yes";
              os = "yes";
              network = "yes";
              packages = "yes";
              ports = {
                "@all" = "no";
                "#text" = "yes";
              };
              processes = "yes";
            }
          ];
          localfile = [
            {
              log_format = "journald";
              location = "journald";
            }
          ];
        };

    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups.${cfg.group} = { };

    systemd.targets.wazuh-agent = {
      description = "Wazuh agent";
      wantedBy = [ "multi-user.target" ];
      wants = map (d: "${d}.service") daemons;
    };

    systemd.services = {
      wazuh-agent-setup = {
        description = "Wazuh agent state directory";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "wazuh-agent";
          ExecStart = setup;
          LoadCredential = lib.optional (
            cfg.enrollment.passwordFile != null
          ) "password:${cfg.enrollment.passwordFile}";
        };
      };
    }
    // lib.genAttrs daemons (d: {
      description = "Wazuh agent ${lib.removePrefix "wazuh-" d}";
      requires = [ "wazuh-agent-setup.service" ];
      after = [
        "wazuh-agent-setup.service"
        "network-online.target"
      ]
      ++ lib.optional (d != "wazuh-agentd") "wazuh-agentd.service";
      wants = [ "network-online.target" ];
      partOf = [ "wazuh-agent.target" ];
      restartTriggers = [ configFile ];
      serviceConfig =
        mounts
        // hardening
        // {
          ExecStart = "${home}/bin/${d} -f";
          Restart = "on-failure";
          RestartSec = 10;
        };
    });
  };
}
