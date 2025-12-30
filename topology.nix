{
  config,
  ...
}:
{
  # Disable the services overview in the main config.
  renderers.elk.overviews.services.enable = false;

  networks.lan = {
    name = "Livebox LAN";
    cidrv4 = "192.168.1.0/24";
  };

  networks.tailscale = {
    name = "Tailscale";
    cidrv4 = "100.64.0.0/10";
  };

  nodes.internet = config.lib.topology.mkInternet {
    connections = config.lib.topology.mkConnection "router" "fiber0";
  };

  nodes.router = config.lib.topology.mkRouter "Router" {
    info = "Livebox 5";
    image = ./docs/_machines/livebox5.png;
    interfaceGroups = [
      [
        "eth1" # Hydra
        "eth2" # Switch
        "wifi"
      ]
      [ "fiber0" ]
    ];
    connections.eth1 = config.lib.topology.mkConnection "netgear" "eth0";
    connections.eth2 = config.lib.topology.mkConnection "hydra" "enp0s31f6";
    connections.wifi = config.lib.topology.mkConnection "scylla" "wlp0s20f3";
    interfaces.eth1.network = "lan";
    interfaces.eth2.network = "lan";
  };

  nodes.netgear = config.lib.topology.mkSwitch "Switch" {
    info = "Netgear GS308";
    image = ./docs/_machines/netgeargs308.png;
    interfaceGroups = [
      [
        "eth0"
        "eth1"
        "eth2"
        "eth3"
      ]
    ];

    connections.eth1 = config.lib.topology.mkConnection "strix" "enp0s31f6";
    connections.eth2 = config.lib.topology.mkConnection "garmr" "enp0s31f6";
    connections.eth3 = config.lib.topology.mkConnection "vapula" "enp0s31f6";

    interfaces.eth0.network = "lan";
    interfaces.eth1.network = "lan";
    interfaces.eth2.network = "lan";
    interfaces.eth3.network = "lan";

  };

  nodes.hydra = {
    interfaces.enp0s31f6 = {
      addresses = [ "192.168.1.71" ]; # Random value, uses DHCP
    };

    interfaces.tailscale0 = {
      addresses = [ "100.64.0.1" ];
      network = "tailscale";
    };
    services.languagetool.hidden = true;
  };

  nodes.scylla = {
    interfaces.wlp0s20f3 = {
      addresses = [ "192.168.1.70" ]; # Random value, uses DHCP
      network = "lan";
    };

    interfaces.tailscale0 = {
      addresses = [ "100.64.0.4" ];
      network = "tailscale";
    };
    services.languagetool.hidden = true;
  };

  nodes.strix = {
    interfaces.tailscale0 = {
      addresses = [ "100.64.0.3" ];
      network = "tailscale";
    };
  };

  nodes.garmr = {
    interfaces.tailscale0 = {
      addresses = [ "100.64.0.5" ];

      network = "tailscale";
    };
  };
  nodes.vapula = {
    interfaces.tailscale0 = {
      addresses = [ "100.64.0.2" ];
      network = "tailscale";
    };
  };

}
