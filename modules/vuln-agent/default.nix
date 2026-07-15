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

    # Host dirs the guest virtiofs-mounts :
    #   nix-store - disk-backing for the writable store overlay (keeps builds off
    #               the guest's RAM-tmpfs root); wiped nightly by vuln-agent-stop
    #   state     - shim logs
    #   secrets   - the assembled runtime env file
    systemd.tmpfiles.rules = [
      "d /var/lib/vuln-agent 0750 root root -"
      "d /var/lib/vuln-agent/nix-store 0755 root root -"
      "d /var/lib/vuln-agent/state 0750 root root -"
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

    # --- Lifecycle: VM exists only 00:00–04:15 -------------------------------
    systemd.services."microvm@${vmName}".wantedBy = lib.mkForce [ ];

    systemd.timers.vuln-agent-start = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-* 00:00:00";
    };
    systemd.services.vuln-agent-start = {
      after = [ "vuln-agent-secrets.service" ];
      wants = [ "vuln-agent-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = "${pkgs.systemd}/bin/systemctl start microvm@${vmName}.service";
    };

    # Shortly after the shim's 04:00 message cutoff: the agent is idle by now, so
    # reclaim the guest RAM and run the nightly store wipe.
    systemd.timers.vuln-agent-stop = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-* 04:15:00";
    };
    systemd.services.vuln-agent-stop = {
      serviceConfig.Type = "oneshot";
      # Stop the VM, then wipe the writable store overlay so agent-built paths
      # don't accumulate unbounded. `systemctl stop` is synchronous, so the
      # virtiofs share is unmounted before we clear its backing dir on the host.
      script = ''
        ${pkgs.systemd}/bin/systemctl stop microvm@${vmName}.service
        rm -rf /var/lib/vuln-agent/nix-store/*
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
