{
  name = "wazuh-agent";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../modules/wazuh-agent/service.nix ];
      services.wazuh-agent = {
        enable = true;
        package = pkgs.callPackage ../packages/wazuh-agent/package.nix { };
        manager.address = "192.0.2.1";
        enrollment.passwordFile = pkgs.writeText "authd.pass" "test";
        settings.localfile = [
          {
            log_format = "syslog";
            location = "/var/log/test.log";
          }
        ];
      };
      systemd.tmpfiles.rules = [ "f /var/log/test.log 0644 root root -" ];
    };

  testScript = ''
    daemons = ["wazuh-agentd", "wazuh-logcollector", "wazuh-syscheckd", "wazuh-modulesd"]
    ossec_log = "/var/lib/wazuh-agent/logs/ossec.log"

    machine.wait_for_unit("wazuh-agent-setup.service")
    for d in daemons:
        machine.wait_for_unit(f"{d}.service")

    with subtest("state tree and password"):
        machine.succeed("test -f /var/lib/wazuh-agent/etc/client.keys")
        machine.succeed("test \"$(stat -c %U:%G /var/lib/wazuh-agent/queue)\" = wazuh:wazuh")
        machine.succeed("test \"$(stat -c %a /var/lib/wazuh-agent/etc/authd.pass)\" = 640")

    with subtest("each daemon sees its home at /var/ossec"):
        pid = machine.succeed("systemctl show -P MainPID wazuh-logcollector").strip()
        machine.succeed(f"nsenter -t {pid} -m test -x /var/ossec/bin/wazuh-logcollector")
        machine.succeed(f"nsenter -t {pid} -m grep -q /var/log/test.log /var/ossec/etc/ossec.conf")

    with subtest("agentd drops to the wazuh user"):
        machine.succeed("test \"$(ps -o user= -C wazuh-agentd)\" = wazuh")

    with subtest("the daemons read the configuration and stay up"):
        machine.wait_until_succeeds(f"grep -q 'wazuh-logcollector.*Analyzing file.*/var/log/test.log' {ossec_log}")
        machine.sleep(20)
        for d in daemons:
            machine.succeed(f"systemctl is-active {d}.service")
        print(machine.succeed(f"cat {ossec_log}"))
        machine.fail(f"grep -E 'CRITICAL|Permission denied|No such file|Failed to load|disabling journal' {ossec_log}")
  '';
}
