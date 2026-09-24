{ ... }:
# Linux audit rules for the Wazuh agent.
#
# The keys (audit-wazuh-*) are the ones that the default Wazuh ruleset
# recognizes (0365-auditd_rules.xml and the etc/lists/audit-keys CDB list).
# Other keys reach the manager, but no rule decodes them into an alert.
{
  security.auditd = {
    enable = true;
    settings = {
      max_log_file = 50;
      num_logs = 5;
      max_log_file_action = "rotate";
    };
  };

  # Do not add -D, -b or -e here: security.audit adds them.
  security.audit.rules = [
    # Commands that a logged-in user runs as root (sudo, su, run0).
    # auid!=unset excludes the daemons, the nix builders and the microvms.
    "-a always,exit -F arch=b64 -S execve,execveat -F euid=0 -F auid>=1000 -F auid!=unset -k audit-wazuh-c"
    "-a always,exit -F arch=b32 -S execve,execveat -F euid=0 -F auid>=1000 -F auid!=unset -k audit-wazuh-c"

    # Identity and privilege files. These are real files on NixOS, not
    # links into /etc/static.
    "-w /etc/sudoers -p wa -k audit-wazuh-w"
    "-w /etc/shadow -p wa -k audit-wazuh-w"
    "-w /etc/passwd -p wa -k audit-wazuh-w"
    "-w /etc/group -p wa -k audit-wazuh-w"
    "-w /root/.ssh -p wa -k audit-wazuh-w"
  ];
}
