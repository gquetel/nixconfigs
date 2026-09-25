{
  lib,
  config,
  nodes,
  ...
}:
let
  cfg = config.services.wazuh-agent;
  manager = lib.importJSON ../wazuh-manager/image.json;
in
{
  imports = [
    ./service.nix
    ../audit
  ];

  services.wazuh-agent = {
    enable = true;
    manager.address = nodes.garmr.config.machine.meta.ipTailscale;
    enrollment.passwordFile = config.age.secrets."wazuh-authd.pass".path;
    settings.localfile = [
      {
        log_format = "audit";
        location = "/var/log/audit/audit.log";
      }
    ];
  };

  assertions = [
    {
      assertion = lib.versionAtLeast manager.version cfg.package.version;
      message = "wazuh-agent ${cfg.package.version} is newer than the manager (${manager.version}). Deploy garmr first.";
    }
  ];

  # journald also receives each audit record, and the journald reader would
  # send it a second time, in a form that the audit decoders do not match.
  # audit.log is the single source.
  systemd.sockets.systemd-journald-audit.enable = false;

  systemd.services.wazuh-agentd = {
    after = [ "tailscale-online.service" ];
    wants = [ "tailscale-online.service" ];
  };

  age.secrets."wazuh-authd.pass".file = ../../secrets/wazuh-authd.pass.age;
  systemd.services.wazuh-agent-setup.restartTriggers = [ ../../secrets/wazuh-authd.pass.age ];
}
