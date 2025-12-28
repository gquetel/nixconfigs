{
  lib,
  config,
  nodes,
  ...
}:

with lib;

let
  cfg = config.wg0;
in
{
  options.wg0 = {
    enable = mkEnableOption "Enable wg0 interface";

    # IP Given by Julien
    ip = mkOption {
      type = types.listOf types.str;
      default = [ "10.100.45.4/24" ];
      description = "Attributed IPV4 IP for my machine in the network.";
    };

    port = mkOption {
      type = types.int;
      default = 51820;
      description = "Port number for Wireguard to listen to.";
    };

  };

  config = mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [ cfg.port ];

    age.secrets.wireguard.file = ../../secrets/wireguard-pvkey.age;

    networking.wireguard.interfaces.wg0 = {
      ips = cfg.ip; 
      allowedIPsAsRoutes = false;

      privateKeyFile = config.age.secrets.wireguard.path;

      listenPort = cfg.port;

      peers = [
        {
          
          publicKey = "oYsN1Qy+a7dwVOKapN5s5KJOmhSflLHZqh+GLMeNpHw=";
          allowedIPs = [ "0.0.0.0/0" ];
          endpoint = "[2001:0bc8:3d24::45]:51821";
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
