# Guest NixOS config for the vulnerability-research microVM.
{
  config,
  lib,
  pkgs,
  inputs,
  vmName ? "vuln-agent",
  vcpu,
  mem,
  ...
}:
let
  claude-code = pkgs.callPackage ../../packages/claude-code { };
  workDir = "/work";
  stateDir = "${workDir}/state";
  secretsEnvFile = "/run/host-secrets/vuln-agent.env";
in
{
  # --------------------------- microVM shell -------------------------------- #
  microvm = {
    hypervisor = "qemu";
    inherit vcpu mem;

    interfaces = [
      {
        type = "tap";
        id = "vm-${vmName}";
        mac = "02:00:00:00:aa:01";
      }
    ];

    # Regarding /nix/store,  a read-only lower layer holds the store the VM boots 
    # from, and agent-built paths land in a read-write upper layer.
    # That upper layer is disk-backed by the nix-cache share below and wiped every night.
    writableStoreOverlay = "/nix/.rw-store";
    shares = [
      {
        source = "/var/lib/vuln-agent/nix-store";
        mountPoint = "/nix/.rw-store";
        tag = "nix-cache";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/state";
        mountPoint = stateDir;
        tag = "state";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/secrets";
        mountPoint = "/run/host-secrets";
        tag = "secrets";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/vuln-agent/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tsstate";
        proto = "virtiofs";
      }
    ];
  };

  # Guest system basic config
  system.stateVersion = "25.05";
  networking.hostName = vmName;
  time.timeZone = "Europe/Paris";
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network = {
    enable = true;
    networks."10-uplink" = {
      matchConfig.MACAddress = "02:00:00:00:aa:01";
      address = [ "10.77.0.2/24" ];
      routes = [ { Gateway = "10.77.0.1"; } ];
      dns = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      linkConfig.RequiredForOnline = "routable";
    };
  };
  services.resolved.enable = true;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "agent"
    ];
  };

  # nixos-container support + KVM for nixosTest VMs
  boot.enableContainers = true;
  boot.kernelModules = [ "kvm-intel" ];
  virtualisation.docker.enable = true; # PoC fallback

  services.tailscale = {
    enable = true;
    authKeyFile = "/run/host-secrets/tailscale.authkey";
    extraUpFlags = [
      "--login-server"
      "https://mesh.gquetel.fr"
    ];
  };

  users.users.agent = {
    isNormalUser = true;
    home = workDir;
    createHome = true;
    extraGroups = [
      "docker"
      "wheel"
    ];
  };

  environment.systemPackages = with pkgs; [
    claude-code
    git
    curl
    jq
    python3
    nixos-container
  ];

  systemd.services.vuln-agent = {
    description = "Autonomous vulnerability-research runner";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      claude-code
      git
      curl
      jq
      docker
      nixos-container
      nix
    ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = workDir;
      EnvironmentFile = secretsEnvFile;

      # Last-message time = operator's 09:00 morning − 5h window, so the shared
      # usage window resets before they return.
      Environment = [
        "VA_CUTOFF=04:00"
      ];
      # Give a pre-accepted ~/.claude.json each boot to prevent hangs.
      ExecStartPre = [
        "${pkgs.coreutils}/bin/install -m0644 ${./../plane/CLAUDE.md} ${workDir}/CLAUDE.md"
        "${pkgs.coreutils}/bin/install -m0600 ${./claude.json} ${workDir}/.claude.json"
      ];
      ExecStart = "${pkgs.python3}/bin/python3 ${./shim.py}";
      StandardOutput = "append:${stateDir}/agent.log";
      StandardError = "inherit";
      RuntimeMaxSec = "8h";
      Restart = "no";
    };
  };
}
