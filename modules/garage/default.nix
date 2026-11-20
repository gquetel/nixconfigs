{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.garage;
in
{
  options.garage = {
    enable = lib.mkEnableOption "Garage S3 object storage, single node";

    host = lib.mkOption {
      type = lib.types.str;
      default = "s3.gquetel.fr";
      description = "Public hostname serving the S3 API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3900;
      description = "Local port of the S3 API.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Reference: https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/
    services.garage = {
      enable = true;
      package = pkgs.garage_2;
      environmentFile = config.age.secrets."garage.env".path;
      settings = {
        replication_factor = 1;
        rpc_bind_addr = "127.0.0.1:3901";
        rpc_public_addr = "127.0.0.1:3901";
        # No root_domain: clients must use path-style requests.
        s3_api = {
          api_bind_addr = "127.0.0.1:${toString cfg.port}";
          s3_region = "garage";
        };
        admin.api_bind_addr = "127.0.0.1:3903";
      };
    };

    age.secrets."garage.env".file = ../../secrets/garage.env.age;

    # Garage authenticates each S3 request with its signature.
    services.nginx.virtualHosts.${cfg.host} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        # Large objects stream to Garage without a size limit or disk buffer.
        extraConfig = ''
          client_max_body_size 0;
          proxy_request_buffering off;
          proxy_buffering off;
        '';
      };
    };
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
