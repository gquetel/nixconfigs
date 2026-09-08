{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# A VM for running AI agents, cut off from the LAN and the mesh.
#
# This module sets up the VM only. Nothing here decides what runs inside it:
# you log in over ssh and start it yourself.
let
  cfg = config.agent-vm;
  vmName = "agent-vm";
  baseDir = "/var/lib/${vmName}";

  # Network interface names cannot be longer than 15 characters.
  tapName = "vm-agent";

  # The VM's `agent` user. Shared folders keep the same user numbers on both
  # sides, so host folders the VM must read have to use this number too.
  agentUid = 1000;

  seedHome = lib.optionalString (cfg.seedFrom != null) config.users.users.${cfg.seedFrom}.home;

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
      echo "guest rebuilt; /work/state, /work/.hermes and the tailscale node are kept"
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

    seedFrom = mkOption {
      type = types.nullOr types.str;
      default = "gquetel";
      description = ''
        Host user whose ~/.hermes/auth.json is copied into the VM every time it
        starts, so you do not have to add the same API keys twice. The copy
        only goes one way. Set to null to copy nothing.
      '';
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = literalExpression "[ config.age.secrets.hermes-plane-token.path ]";
      description = ''
        KEY=VALUE files joined into one file the VM reads at
        /run/agent-secrets/env. For keys that do not live in auth.json, such as
        the Plane token. Whatever runs in the VM has to read that file itself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The VM runs VMs of its own to test things in.
    boot.extraModprobeConfig = "options kvm-intel nested=1";

    environment.systemPackages = [ reset ];

    systemd.tmpfiles.rules = [
      "d ${baseDir}           0750 root root -"
      "d ${baseDir}/nix-store 0755 root root -"
      "d ${baseDir}/disk      0700 microvm kvm -"
      "d ${baseDir}/state     0775 root wheel -"
      # These two must belong to the VM's user, or the VM cannot open them.
      "d ${baseDir}/secrets   0700 ${toString agentUid} root -"
      "d ${baseDir}/hermes    0700 ${toString agentUid} root -"
      "d ${baseDir}/tailscale 0700 root root -"
      "a+ ${baseDir} - - - - u:microvm:x"
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

        ${lib.optionalString (cfg.seedFrom != null) ''
          if [ -f ${seedHome}/.hermes/auth.json ]; then
            install -m0600 -o ${toString agentUid} -g root \
              ${seedHome}/.hermes/auth.json ${baseDir}/hermes/auth.json
          fi
        ''}

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
          ;
        inherit (cfg) mem disk;
      };
      config = import ./guest.nix;
      # Runs here last for hours. A deploy must not cut one short, so config
      # changes only apply when the VM is rebooted.
      restartIfChanged = false;
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
    # reach. The last rule stops the VM from connecting to this host; it only
    # needs us to pass its traffic on.
    networking.firewall.extraCommands = ''
      # ${vmName} (10.77.0.0/24): internet only, no LAN, mesh, or VPN.
      iptables -I FORWARD -s 10.77.0.0/24 -d 192.168.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 10.0.0.0/8     -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 172.16.0.0/12  -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 169.254.0.0/16 -j DROP
      iptables -I FORWARD -s 10.77.0.0/24 -d 100.64.0.0/10  -j DROP
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
  };
}
