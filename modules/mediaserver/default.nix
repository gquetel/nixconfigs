{
  lib,
  config,
  nodes,
  pkgs,
  ...
}:
{

  # ----------------- mediaserver user & group -----------------
  users.groups.mediaserver = {
    name = "mediaserver";
  };

  users.users.mediaserver = {
    name = "mediaserver";
    isNormalUser = true;
    home = "/home/mediaserver";
    group = "mediaserver";
  };

  # ----------------- Services -----------------
  services.sonarr = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.radarr = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.jellyfin = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.jackett = {
    enable = true;
    user = "mediaserver";
    group = "mediaserver";
  };

  services.deluge = {
    enable = true;
    authFile = "/home/mediaserver/.deluge-info";
    user = "mediaserver";
    group = "mediaserver";
    declarative = true;
    openFirewall = false;
    web.enable = true;
    config = {
      download_location = "/mmedia/deluge/";
      enabled_plugins = [ "Label" ];
      allow_remote = true;
      max_active_seeding = 50;
      max_active_downloading = 10;
      max_active_limit = 60;
    };
  };

  services.jellyseerr = {
    enable = true;
    port = 8097;
    package = pkgs.unstable.jellyseerr;
  };

  # ----------------- Nginx reverse proxy -----------------
  # Don't forget to add 127.0.0.1 to known proxies in Jellyfin's config 
  # see https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/.
  services.nginx.virtualHosts."movies.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;
    };
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };

  services.nginx.virtualHosts."dmd.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8097";
    };
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };

  services.nginx.virtualHosts."deluge.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 443;
        ssl = true;
      }
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 80;
      }
    ];
    locations."/" = {
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:8112";
    };
  };
  security.acme.certs."deluge.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  services.nginx.virtualHosts."veste.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 443;
        ssl = true;
      }
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 80;
      }
    ];
    locations."/" = {
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:9117";
    };
  };
  security.acme.certs."veste.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  services.nginx.virtualHosts."sonarr.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 443;
        ssl = true;
      }
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 80;
      }
    ];
    locations."/" = {
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:8989";
    };
  };
  security.acme.certs."sonarr.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  services.nginx.virtualHosts."radarr.mesh.gq" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 443;
        ssl = true;
      }
      {
        addr = nodes.vapula.config.machine.meta.ipTailscale;
        port = 80;
      }
    ];
    locations."/" = {
      extraConfig = "
      allow 100.64.0.0/10;
      allow  fd7a:115c:a1e0::/48;
      deny all;";
      proxyPass = "http://127.0.0.1:7878";
    };
  };
  security.acme.certs."radarr.mesh.gq".server = "https://ca.mesh.gq/acme/acme/directory";

  # ----------------- Other -----------------
  # fail2ban rules for too many authentication attempts.
  environment.etc = {
    "fail2ban/filter.d/jellyfin.conf".text = ''
      [Definition]
            failregex = ^.*Authentication request for .* has been denied \(IP: "?<ADDR>"?\)\.'';

    "fail2ban/jail.d/jellyfin.local".text = ''
      [jellyfin]
            backend = auto
            enabled = true
            port = 80,443
            protocol = tcp
            filter = jellyfin
            maxretry = 5
            bantime = 36000
            findtime = 3600
            logpath = /var/lib/jellyfin/log/log_*'';
  };

}
