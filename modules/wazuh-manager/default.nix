{
  lib,
  config,
  pkgs,
  ...
}:
# Wazuh manager (https://wazuh.com), the declarative equivalent of the
# manager service in the upstream wazuh-docker single-node stack.
#
# Manager only: no indexer and no dashboard. Alerts go to
# logs/alerts/alerts.json in the `logs` volume. Filebeat in the image has no
# indexer to send to and retries; the manager daemons run regardless.
#
# Runs rootless, as modules/plane does: a dedicated `wazuh-manager` user owns
# the container through home-manager's `services.podman` (Quadlet units under
# the user's systemd instance).
let
  cfg = config.wazuh-manager;

  user = "wazuh-manager";
  home = "/var/lib/wazuh-manager";

  # Version, image digest and config hash. packages/wazuh-agent/update.sh
  # writes this file, for the agent and the manager together.
  pin = lib.importJSON ./image.json;
  inherit (pin) version;

  image = "docker.io/wazuh/wazuh-manager:${version}@${pin.digest}";

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
    # These two need the indexer.
    [
      "<vulnerability-detection>\n    <enabled>yes</enabled>"
      "<vulnerability-detection>\n    <enabled>no</enabled>"
    ]
    [
      "<indexer>\n    <enabled>yes</enabled>"
      "<indexer>\n    <enabled>no</enabled>"
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

  authdPass = config.age.secrets."wazuh-authd.pass".path;
in
{
  options.wazuh-manager = {
    enable = lib.mkEnableOption "Wazuh manager";
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

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${user} = {
      home.stateVersion = "25.05";
      services.podman = {
        enable = true;
        containers.wazuh-manager = {
          inherit image;
          # Published on all addresses: a user unit cannot wait for the
          # tailscale IP. The host firewall keeps both ports closed, except on
          # the trusted tailscale0 interface.
          # 1514: agent events (remoted). 1515: enrollment (authd).
          ports = [
            "1514:1514"
            "1515:1515"
          ];
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
            "${ossecConf}:/wazuh-config-mount/etc/ossec.conf:ro"
            "${authdPass}:/wazuh-config-mount/etc/authd.pass:ro"
          ];
          # Changes the unit when the password changes, so that the container
          # restarts and reads the new authd.pass.
          environment.AUTHD_PASS_REVISION = builtins.hashFile "sha256" ../../secrets/wazuh-authd.pass.age;
          extraPodmanArgs = [ "--security-opt=no-new-privileges" ];
        };
      };
    };

    age.secrets."wazuh-authd.pass" = {
      file = ../../secrets/wazuh-authd.pass.age;
      owner = user;
      group = user;
    };
  };
}
