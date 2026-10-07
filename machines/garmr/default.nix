{ ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/fail2ban
    ../../modules/fish
    ../../modules/tailscale
    ../../modules/headscale
    ../../modules/step-ca
    ../../modules/servers
    ../../modules/grafana
    ../../modules/plane
    ../../modules/prometheus
    ../../modules/wazuh-agent
    ../../modules/wazuh-manager
    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # ---------------- Automatically generated  ----------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };
  console.keyMap = "fr";

  # ---------------- My config  ----------------
  machine.meta = {
    ipTailscale = "100.64.0.5";
  };

  # ---------------- Networking  ----------------
  servers.lanAddresses = [
    "192.168.1.28/24"
    "2a01:cb00:253:ed00::0005/64"
  ];
  systemd.network.networks."10-wired".networkConfig.IPv6AcceptRA = true;

  networking = {
    hostName = "garmr";
    firewall.allowedTCPPorts = [
      22
      80
    ];
    # Ports 443 and 444 are only reachable from strix (SNI proxy) over IPv6.
    # All public HTTPS traffic must transit strix; direct connections to this
    # backend's TLS ports from the LAN or the internet are dropped.
    firewall.extraCommands = ''
      ip6tables -A nixos-fw -p tcp --dport 443 -s 2a01:cb00:253:ed00::3 -j nixos-fw-accept
      ip6tables -A nixos-fw -p tcp --dport 444 -s 2a01:cb00:253:ed00::3 -j nixos-fw-accept
    '';
  };

  # ---------------- Deployment info ----------------
  deployment.targetHost = "garmr";
  deployment.targetUser = "root";

  # ---------------- Services ----------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  # ---------------- Modules ----------------
  programs.rust-motd.settings.service_status = {
    headscale = "headscale";
    tailscale = "tailscaled";
    prometheus = "prometheus";
    prometheus_node_exporter = "prometheus-node-exporter";
    step-ca = "step-ca";
  };

  grafana.enable = true;
  plane.enable = true;
  prometheus.enable = true;
  wazuh-manager = {
    enable = true;
    admins = [ "gquetel@mail.foo.gq" ];
  };

  # ---------------- age secrets ----------------
  age.secrets.step-ca-pwd.file = ../../secrets/step-ca.pwd.age;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
