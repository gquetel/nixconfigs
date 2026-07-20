# Host module: the agent-based microVM
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.autonomous-agent;
  vmName = "autonomous-agent";
  stateDir = "/var/lib/autonomous-agent/state";
  metricsDir = "/var/lib/autonomous-agent/metrics";
  agentRuntime = inputs.agent-runtime;

  # Guest TAP device name. Kept short and independent of vmName because Linux
  # interface names are capped at 15 chars (IFNAMSIZ), which vm-${vmName} exceeds.
  tapName = "vm-agent";

  # Space-separated allow-list of profile names manual runs may request.
  validProfiles = lib.concatStringsSep " " cfg.profiles;

  agent-run = pkgs.writeShellApplication {
    name = "agent-run";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      S=${stateDir}
      if [ "''${1:-}" = "--status" ]; then
        if [ ! -f "$S/status.json" ]; then
          echo "no status recorded yet (agent hasn't started since the last recycle)"
          exit 0
        fi
        jq -r '
          "mode:             " + .mode,
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
      fi
      if [ "''${1:-}" = "--stop" ]; then
        rm -f "$S/stop.trigger"; : > "$S/stop.trigger"
        echo "stop requested; the guest poller will end the session within ~30s"
        exit 0
      fi
      profile="''${1:-}"
      if [ -z "$profile" ] || [ "''${profile#--}" != "$profile" ]; then
        echo "usage: agent-run <profile> [prompt...] | agent-run --status | agent-run --stop" >&2
        echo "profiles: ${validProfiles}" >&2
        exit 2
      fi
      known=0
      for p in ${validProfiles}; do
        [ "$p" = "$profile" ] && known=1 && break
      done
      if [ "$known" -ne 1 ]; then
        echo "unknown profile '$profile' (known: ${validProfiles})" >&2
        exit 2
      fi
      shift
      prompt="''${*:-}"
      # Trigger encodes profile on line 1, the prompt (may be empty) after it.
      # Written via a temp file + mv so the guest poller never reads it half-written.
      tmp="$(mktemp "$S/.manual.XXXXXX")"
      { printf '%s\n' "$profile"; printf '%s' "$prompt"; } > "$tmp"
      mv -f "$tmp" "$S/manual.trigger"
      echo "manual run requested (profile=$profile, prompt=''${prompt:-<default>}); starts within ~30s, runs up to 60 min"
      echo "watch: tail -f $S/agent.log"
    '';
  };
in
{
  imports = [
    "${inputs."microvm.nix"}/nixos-modules/host"
  ];

  options.autonomous-agent = {
    enable = lib.mkEnableOption "autonomous agent microVM (Claude Code, Plane-backed)";
    vcpu = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };
    mem = lib.mkOption {
      type = lib.types.int;
      default = 10240;
      description = "Guest RAM in MiB";
    };
    nightlyProfile = lib.mkOption {
      type = lib.types.str;
      default = "vuln";
      description = ''
        Profile the nightly run uses. This modify the file nightly.profile on every configuration apply. Then, instead of going back and forth in the config, we can edit that file on the host.
      '';
    };
    profiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "vuln" ];
      description = "Profile names agent-run accepts for manual runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Nested KVM so the guest can run `runNixOSTest` VMs
    boot.extraModprobeConfig = "options kvm-intel nested=1";

    environment.systemPackages = [ agent-run ];

    systemd.tmpfiles.rules = [
      "d /var/lib/autonomous-agent 0750 root wheel -"
      "d /var/lib/autonomous-agent/nix-store 0755 root root -"
      "d /var/lib/autonomous-agent/state 0775 root wheel -"
      "d /var/lib/autonomous-agent/secrets 0750 root root -"
      "d /var/lib/autonomous-agent/tailscale 0700 root root -"
      "d /var/lib/autonomous-agent/disk 0700 microvm kvm -"
      "d /var/lib/autonomous-agent/metrics 0755 root root -"
      "a+ /var/lib/autonomous-agent - - - - u:microvm:x"
      # Profile selector. Create-only, so host edits are not overwritten.
      "f ${stateDir}/nightly.profile 0664 root wheel - ${cfg.nightlyProfile}"
    ];

    # Refresh the textfile-collector metric every 30s, matching the guest
    # poller's own trigger-file poll interval.
    systemd.timers.autonomous-agent-metrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        Unit = "autonomous-agent-metrics.service";
      };
    };
    systemd.services.autonomous-agent-metrics = {
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${agentRuntime}/autonomous_agent.py metrics ${stateDir}/status.json ${metricsDir}/autonomous_agent.prom";
      };
    };

    # Textfile collector: exposes the metrics above through the node exporter
    # already enabled on this host (machines/vapula/default.nix).
    services.prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=${metricsDir}" ];
    };

    # We rotate the agent's append-only stream log
    services.logrotate.enable = true;
    services.logrotate.settings."/var/lib/autonomous-agent/state/agent.log" = {
      su = "root root";
      frequency = "daily";
      rotate = 14;
      compress = true;
      delaycompress = true;
      copytruncate = true;
      missingok = true;
      notifempty = true;
    };

    # Assemble the guest env file from the decrypted age secrets. Kept out of the
    # store; only the guest reads it.  It contains: Claude OAuth + Plane + Tailscale creds.
    systemd.services.autonomous-agent-secrets = {
      wantedBy = [ "multi-user.target" ];
      after = [ "agenix-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        umask 077
        # Runner env: Claude OAuth + Plane only.
        {
          printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$(cat ${config.age.secrets.claude-oauth-token.path})"
          cat ${config.age.secrets."plane-agent.env".path}
        } > /var/lib/autonomous-agent/secrets/autonomous-agent.env
        # Bare Tailscale authkey file.
        cat ${config.age.secrets.tailscale-authkey.path} > /var/lib/autonomous-agent/secrets/tailscale.authkey
      '';
    };

    microvm.vms.${vmName} = {
      specialArgs = {
        inherit inputs vmName tapName;
        inherit (cfg) vcpu mem nightlyProfile;
      };
      config = import ./guest.nix;
      # If i want to prevent agent being killed mid-session this should be set to false
      # but, then, any new deploy will only be taken into account on next reboot,
      # i don't want that right now that i modify it a lot.
      # TODO: probably switch to false at some point
      restartIfChanged = true;
    };

    # The VM runs 24/7, and is wiped down every monday morning.
    systemd.services."microvm@${vmName}" = {
      wantedBy = lib.mkForce [ "multi-user.target" ];
      after = [ "autonomous-agent-secrets.service" ];
      wants = [ "autonomous-agent-secrets.service" ];
    };

    systemd.timers.autonomous-agent-recycle = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "Mon *-*-* 08:00:00";
    };
    systemd.services.autonomous-agent-recycle = {
      after = [ "autonomous-agent-secrets.service" ];
      wants = [ "autonomous-agent-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.systemd}/bin/systemctl stop microvm@${vmName}.service
        rm -rf /var/lib/autonomous-agent/nix-store/*
        rm -f /var/lib/autonomous-agent/disk/root.img
        rm -f /var/lib/autonomous-agent/state/manual.trigger \
              /var/lib/autonomous-agent/state/stop.trigger \
              /var/lib/autonomous-agent/state/manual.prompt \
              /var/lib/autonomous-agent/state/manual.profile
        ${pkgs.systemd}/bin/systemctl start microvm@${vmName}.service
      '';
    };

    # --- Network fence: NAT bridge, LAN/mesh blocked except Plane ------------
    # Guest TAP joins its own NAT bridge (10.77.0.0/24), masqueraded out the WAN
    # uplink only. Plane is reached via the guest's own Tailscale node.
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
    # Enslave the microvm TAP to the bridge. microvm.nix creates it via
    # `ip tuntap add name ${tapName}` (= the interface `id`) with no host-side
    # networkd file of its own, so this is the intended bridging idiom.
    systemd.network.networks."40-agent-tap" = {
      matchConfig.Name = tapName;
      networkConfig.Bridge = "br-agent";
      linkConfig.RequiredForOnline = "no";
    };

    # Masquerade the guest subnet out the physical WAN uplink (never wg0).
    networking.nat = {
      enable = true;
      externalInterface = "enp0s31f6";
      internalIPs = [ "10.77.0.0/24" ];
    };

    # WAN egress is allowed by the ACCEPT FORWARD policy; we only DROP the
    # private/mesh destinations the guest must never reach, plus refuse guest ->
    # host input (it uses public DNS, needs the host only as a router).
    networking.firewall.extraCommands = ''
      # autonomous-agent guest (10.77.0.0/24): WAN only — no LAN, mesh, or wg net.
      iptables -I FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP  # tailscale mesh
      iptables -I nixos-fw 1 -i br-agent -j nixos-fw-refuse
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP 2>/dev/null || true
      iptables -D nixos-fw -i br-agent -j nixos-fw-refuse 2>/dev/null || true
    '';

    # --- age secrets ------
    age.secrets.claude-oauth-token.file = ../../secrets/claude-oauth-token.age;
    age.secrets."plane-agent.env".file = ../../secrets/plane-agent.env.age;
    age.secrets.tailscale-authkey.file = ../../secrets/tailscale-authkey.age;
  };
}
