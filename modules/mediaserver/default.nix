{ config, pkgs, ... }:
{

  # ----------------- mediaserver user & group -----------------
  users.groups.mediaserver = { };

  users.users.mediaserver = {
    isNormalUser = true;
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
    package = pkgs.unstable.jackett;
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
      max_active_seeding = 200;
      max_active_downloading = 10;
      max_active_limit = 200;
      listen_ports = [
        56881
        56881
      ];
    };
  };

  systemd.services.deluged = config.mullvad.confine;
  mullvad.proxies.deluge-rpc = {
    listen = "127.0.0.1:58846";
    connect = "127.0.0.1:58846";
  };

  services.seerr = {
    enable = true;
    port = 8097;
    package = pkgs.unstable.seerr;
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
      # Allows ACME requests in.
      {
        addr = "[::]";
        port = 80;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };

  tailnet.vhosts = {
    "deluge.mesh.gq".proxyPass = "http://127.0.0.1:8112";
    "veste.mesh.gq".proxyPass = "http://127.0.0.1:9117";
    "sonarr.mesh.gq".proxyPass = "http://127.0.0.1:8989";
    "radarr.mesh.gq".proxyPass = "http://127.0.0.1:7878";
  };

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
