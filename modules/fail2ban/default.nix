{
  lib,
  config,
  pkgs,
  ...
}:

{

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "24h";
    bantime-increment.multipliers = "1 2 4 8 16 32 64";
    # Never ban headscale/tailscale peers (CGNAT range).
    ignoreIP = [ "100.64.0.0/10" ];

    # Ban bots that scan for non-existent paths.
    jails.nginx-404-scan = {
      settings = {
        backend = "auto";
        logpath = "/var/log/nginx/access.log";
        findtime = 600;
        maxretry = 10;
      };
      filter.Definition = {
        # Custom filter to match vcombined format.
        failregex = ''^\S+ <HOST> \- \S+ \[\] "[A-Z]+ [^"]*" 404 \d+ ".*?" ".*?"$'';
        # Don't count benign browser auto-requests (favicon, apple-touch-icons,
        # robots.txt, /.well-known/*) toward the ban threshold.
        ignoreregex = ''"[A-Z]+ /(favicon\.ico|apple-touch-icon[^ ]*|robots\.txt|\.well-known/[^ ]*) '';
        datepattern = "%%d/%%b/%%Y:%%H:%%M:%%S %%z";
      };
    };
  };

  # Required by fail2ban
  services.openssh.settings.LogLevel = "VERBOSE";
}
