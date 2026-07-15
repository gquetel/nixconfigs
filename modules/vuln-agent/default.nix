# Host module: the nightly vulnerability-research microVM
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.vuln-agent;
  vmName = "vuln-agent";
  stateDir = "/var/lib/vuln-agent/state";

  # Custom script to manually run the vuln-research agent.
  vuln-agent-run = pkgs.writeShellApplication {
    name = "vuln-agent-run";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      S=${stateDir}
      if [ "''${1:-}" = "--stop" ]; then
        rm -f "$S/stop.trigger"; : > "$S/stop.trigger"
        echo "stop requested; the guest poller will end the session within ~30s"
        exit 0
      fi
      prompt="''${*:-}"
      # rm first in case a stale root-owned trigger lingers.
      rm -f "$S/manual.trigger"
      printf '%s' "$prompt" > "$S/manual.trigger"
      echo "manual run requested (prompt=''${prompt:-<default>}); starts within ~30s, runs up to 60 min"
      echo "watch: tail -f $S/agent.log"
    '';
  };
in
{
  imports = [
    "${inputs."microvm.nix"}/nixos-modules/host"
  ];

  options.vuln-agent = {
    enable = lib.mkEnableOption "nightly autonomous vulnerability-research microVM";
    vcpu = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };
    mem = lib.mkOption {
      type = lib.types.int;
      default = 10240;
      description = "Guest RAM in MiB";
    };
  };

  config = lib.mkIf cfg.enable {
    # Nested KVM so the guest can run `runNixOSTest` VMs
    boot.extraModprobeConfig = "options kvm-intel nested=1";

    environment.systemPackages = [ vuln-agent-run ];

    # Host dirs the guest virtiofs-mounts. state/ is 0775 root:wheel so wheel can
    # drop triggers without sudo and o+rx lets the agent-user shim read
    # manual.prompt; parent 0750 root:wheel gives wheel traversal only.
    systemd.tmpfiles.rules = [
      "d /var/lib/vuln-agent 0750 root wheel -"
      "d /var/lib/vuln-agent/nix-store 0755 root root -"
      "d /var/lib/vuln-agent/state 0775 root wheel -"
      "d /var/lib/vuln-agent/secrets 0750 root root -"
      "d /var/lib/vuln-agent/tailscale 0700 root root -"
    ];

    # Assemble the guest env file from the decrypted age secrets. Kept out of the
    # store; only the guest reads it.
    # It contains: Claude OAuth + Plane + Tailscale creds.

    systemd.services.vuln-agent-secrets = {
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
        } > /var/lib/vuln-agent/secrets/vuln-agent.env
        # Bare Tailscale authkey file.
        cat ${config.age.secrets.tailscale-authkey.path} > /var/lib/vuln-agent/secrets/tailscale.authkey
      '';
    };

    microvm.vms.${vmName} = {
      specialArgs = {
        inherit inputs vmName;
        inherit (cfg) vcpu mem;
      };
      config = import ./guest.nix;
    };

    # --- Lifecycle: VM up 24/7, recycled once a day --------------------------
    # Sessions are gated inside the guest (23:00 timer / trigger), not the VM.
    systemd.services."microvm@${vmName}" = {
      wantedBy = lib.mkForce [ "multi-user.target" ];
      after = [ "vuln-agent-secrets.service" ];
      wants = [ "vuln-agent-secrets.service" ];
    };

    # Daily 08:00 reset: stop → wipe the host-backed store overlay → start (a
    # guest reboot can't wipe it; the synchronous stop unmounts the share first).
    # Kills any live session by design.
    systemd.timers.vuln-agent-recycle = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-* 08:00:00";
    };
    systemd.services.vuln-agent-recycle = {
      after = [ "vuln-agent-secrets.service" ];
      wants = [ "vuln-agent-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.systemd}/bin/systemctl stop microvm@${vmName}.service
        rm -rf /var/lib/vuln-agent/nix-store/*
        rm -f /var/lib/vuln-agent/state/manual.trigger \
              /var/lib/vuln-agent/state/stop.trigger \
              /var/lib/vuln-agent/state/manual.prompt
        ${pkgs.systemd}/bin/systemctl start microvm@${vmName}.service
      '';
    };

    # --- Network fence: NAT bridge, LAN/mesh blocked except Plane ------------
    # Guest TAP joins its own NAT bridge (10.77.0.0/24), masqueraded out the WAN
    # uplink only. Plane is reached via the guest's own Tailscale node.
    systemd.network.netdevs."40-br-vuln" = {
      netdevConfig = {
        Kind = "bridge";
        Name = "br-vuln";
      };
    };
    systemd.network.networks."40-br-vuln" = {
      matchConfig.Name = "br-vuln";
      address = [ "10.77.0.1/24" ];
      networkConfig.ConfigureWithoutCarrier = true;
      linkConfig.RequiredForOnline = "no";
    };
    # Enslave the microvm TAP to the bridge. microvm.nix creates it via
    # `ip tuntap add name vm-<vmName>` (= the interface `id`) with no host-side
    # networkd file of its own, so this is the intended bridging idiom.
    systemd.network.networks."40-vuln-tap" = {
      matchConfig.Name = "vm-${vmName}";
      networkConfig.Bridge = "br-vuln";
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
      # vuln-agent guest (10.77.0.0/24): WAN only — no LAN, mesh, or wg net.
      iptables -I FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP  # tailscale mesh
      iptables -I nixos-fw 1 -i br-vuln -j nixos-fw-refuse
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP 2>/dev/null || true
      iptables -D FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP 2>/dev/null || true
      iptables -D nixos-fw -i br-vuln -j nixos-fw-refuse 2>/dev/null || true
    '';

    # --- age secrets ------
    age.secrets.claude-oauth-token.file = ../../secrets/claude-oauth-token.age;
    age.secrets."plane-agent.env".file = ../../secrets/plane-agent.env.age;
    age.secrets.tailscale-authkey.file = ../../secrets/tailscale-authkey.age;
  };
}
