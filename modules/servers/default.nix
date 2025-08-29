{
  lib,
  config,
  pkgs,
  ...
}:
{

  # motd
  # https://github.com/rust-motd/rust-motd
  programs.rust-motd = {
    enable = true;
    order = [
      "filesystems"
      "memory"
      "last_login"
      "uptime"
      "service_status"
      "fail_2_ban"
    ];
    # Config Error: unknown field `fail2ban`, expected one of `global`, `banner`, `cg_stats`,
    # `docker`, `fail_2_ban`, `filesystems`, `last_login`, `last_run`, `load_avg`, `memory`, `service_status`,
    #  `user_service_status`, `ssl_certificates`, `uptime`, `weather` at line 17 column 1

    settings = {
      uptime.prefix = "Up";
      service_status.nginx = "nginx";
      filesystems.root = "/";
      last_login.gquetel = 3;
      filesystems.boot = "/boot";
      memory.swap_pos = "none";
      fail_2_ban.jails = [ "sshd" ];
    };
  };
  systemd.services.rust-motd.path = [ pkgs.fail2ban ];
}
