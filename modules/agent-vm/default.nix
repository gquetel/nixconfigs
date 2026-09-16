{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# A VM for running AI agents, cut off from the LAN and the mesh.
#
# This module sets up the VM and the `agent-run` CLI that starts a session in
# it. It does not know what the agent does: the driver and the per-project
# profiles live in a private repo that the VM clones when it runs.
let
  cfg = config.agent-vm;
  vmName = "agent-vm";
  baseDir = "/var/lib/${vmName}";

  # Network interface names cannot be longer than 15 characters.
  tapName = "vm-agent";

  # The VM's `agent` user. Shared folders keep the same user numbers on both
  # sides, so host folders the VM must read have to use this number too.
  agentUid = 1000;

  vmIp = "10.77.0.2";

  # The guest command that `agent-run` starts over ssh. Defined in guest.nix.
  launcherName = "agent-session";

  reset = pkgs.writeShellApplication {
    name = "agent-vm-reset";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
    ];
    text = ''
      systemctl stop microvm@${vmName}.service
      rm -rf ${baseDir}/nix-store/*
      rm -f ${baseDir}/disk/root.img
      systemctl start microvm@${vmName}.service
      echo "guest rebuilt; /work/state and the tailscale node are kept"
    '';
  };

  # The operator front end. Everything it needs is on the host: the session
  # runs in a tmux in the VM, and the agent writes its status and its log to
  # the shared state folder. It does not know which profiles exist. They live
  # in the private runtime repo, and Nix must not have to list them.
  agent-run = pkgs.writeShellApplication {
    name = "agent-run";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      openssh
    ];
    text = ''
      S=${baseDir}/state

      case "''${1:-}" in
        --status)
          # An unreadable folder looks the same as a missing file, and the VM
          # writes there as a different user, so tell the two apart here.
          if [ ! -r "$S" ]; then
            echo "cannot read $S; you must be in the wheel group" >&2
            exit 1
          fi
          if [ ! -f "$S/status.json" ]; then
            echo "no status yet; no session has run since the last reset"
            exit 0
          fi
          jq -r '
            "profile:          " + (.profile // "-"),
            "state:            " + .state,
            "updated_at:       " + .updated_at,
            "started_at:       " + (.started_at // "-"),
            "stop_at:          " + (.stop_at // "-"),
            "last_heartbeat:   " + (.last_heartbeat // "-"),
            "last_exit_reason: " + (.last_exit_reason // "-"),
            "last_exit_at:     " + (.last_exit_at // "-")
          ' "$S/status.json"
          exit 0
          ;;
        --stop)
          : > "$S/stop.trigger"
          echo "stop requested; the session stops before its next iteration"
          exit 0
          ;;
        "" | --*)
          echo "usage: agent-run <profile> [driver option...] [--] [prompt...] | agent-run --status | agent-run --stop" >&2
          exit 2
          ;;
      esac

      profile="$1"
      shift
      # Two levels of quoting: ssh gives the string to the guest shell, which
      # gives the inner string to tmux, which runs it with sh -c.
      inner="$(printf '%q ' ${launcherName} "$profile" "$@")"
      # A reset gives the VM new host keys, so there is nothing stable to check.
      ssh -t \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        agent@${vmIp} "tmux new -As agent $(printf '%q' "$inner")"
    '';
  };
in
{
  imports = [
    "${inputs."microvm.nix"}/nixos-modules/host"
  ];

  options.agent-vm = with lib; {
    enable = mkEnableOption "VM for running AI agents";

    mem = mkOption {
      type = types.int;
      default = 10240;
      description = "VM memory in MiB.";
    };

    disk = mkOption {
      type = types.int;
      default = 51200;
      description = ''
        VM disk in MiB. Holds cloned code, Docker images, and whatever the VM
        builds with nix.
      '';
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = literalExpression "[ config.age.secrets.hermes-plane-token.path ]";
      description = ''
        KEY=VALUE files joined into one file the VM reads at
        /run/agent-secrets/env. This is the only path credentials take into the
        VM. Whatever runs in the VM has to read that file itself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The VM runs VMs of its own to test things in.
    boot.extraModprobeConfig = "options kvm-intel nested=1";

    environment.systemPackages = [
      reset
      agent-run
    ];

    systemd.tmpfiles.rules = [
      "d ${baseDir}           0750 root root -"
      "d ${baseDir}/nix-store 0755 root root -"
      "d ${baseDir}/disk      0700 microvm kvm -"
      "d ${baseDir}/state     0775 root wheel -"
      # These two must belong to the VM's user, or the VM cannot open them.
      "d ${baseDir}/secrets   0700 ${toString agentUid} root -"
      "d ${baseDir}/config    0700 ${toString agentUid} root -"
      "d ${baseDir}/tailscale 0700 root root -"
      # microvm must reach the VM's files, and wheel must reach state/ for
      # `agent-run --status` and `--stop`. Traverse only: neither one can list
      # ${baseDir} itself.
      "a+ ${baseDir} - - - - u:microvm:x,g:wheel:x"
    ];

    # Runs every time the VM starts, so new keys on the host reach the VM after
    # a restart.
    systemd.services.agent-vm-secrets = {
      description = "Copy credentials into ${vmName}";
      after = [ "agenix-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        umask 077

        ${lib.optionalString (cfg.environmentFiles != [ ]) ''
          # The extra newline stops the last line of one file from being glued
          # to the first line of the next.
          for f in ${lib.escapeShellArgs cfg.environmentFiles}; do
            cat "$f"
            echo
          done > ${baseDir}/secrets/env
          chown ${toString agentUid}:root ${baseDir}/secrets/env
          chmod 0600 ${baseDir}/secrets/env
        ''}
      '';
    };

    microvm.vms.${vmName} = {
      specialArgs = {
        inherit
          inputs
          vmName
          tapName
          baseDir
          agentUid
          vmIp
          launcherName
          ;
        inherit (cfg) mem disk;
      };
      config = import ./guest.nix;
      restartIfChanged = true;
    };

    systemd.services."microvm@${vmName}" = {
      wantedBy = lib.mkForce [ "multi-user.target" ];
      after = [ "agent-vm-secrets.service" ];
      wants = [ "agent-vm-secrets.service" ];
    };

    # --- Network -------------------------------------------------------------
    # The VM gets its own small network (10.77.0.0/24) with internet access
    # through this host. It reaches the mesh through its own tailscale, not
    # through us.
    systemd.network.netdevs."40-br-agent" = {
      netdevConfig = {
        Kind = "bridge";
        Name = "br-agent";
      };
    };
    systemd.network.networks."40-br-agent" = {
      matchConfig.Name = "br-agent";
      address = [ "10.77.0.1/24" ];
      networkConfig.ConfigureWithoutCarrier = true;
      linkConfig.RequiredForOnline = "no";
    };
    # microvm.nix makes the VM's network interface but does not attach it to
    # anything, so we attach it to the bridge here.
    systemd.network.networks."40-agent-tap" = {
      matchConfig.Name = tapName;
      networkConfig.Bridge = "br-agent";
      linkConfig.RequiredForOnline = "no";
    };

    networking.nat = {
      enable = true;
      externalInterface = "enp0s31f6";
      internalIPs = [ "10.77.0.0/24" ];
    };

    # The internet is already allowed, so we only block what the VM must never
    # reach. The last two rules stop the VM from opening a connection to this
    # host, but keep the answers to the ones we open, such as the ssh of
    # `agent-run`. Both go above the accept rules of nixos-fw.
    networking.firewall.extraCommands = ''
      # ${vmName} (10.77.0.0/24): internet only, no LAN, mesh, or VPN.
      iptables -I FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP
      iptables -I nixos-fw 1 -i br-agent -j nixos-fw-refuse
      iptables -I nixos-fw 1 -i br-agent -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP 2>/dev/null || true
      iptables -D nixos-fw -i br-agent -j nixos-fw-refuse 2>/dev/null || true
      iptables -D nixos-fw -i br-agent -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept 2>/dev/null || true
    '';
  };
}
