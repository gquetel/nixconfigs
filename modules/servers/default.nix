{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfgmotd = config.servers.motd;
  format = pkgs.formats.toml { };
in
{

  # motd. We want each machine to customize displayed services hence the options.
  # https://github.com/rust-motd/rust-motd
  options.servers.motd = {
    enable = mkEnableOption "motd on servers";
    order = mkOption {
      type = types.listOf types.str;
      default = [
        "filesystems"
        "memory"
        "last_login"
        "uptime"
        "service_status"
        "fail_2_ban"
      ];
    };

    settings = mkOption {
      type = types.attrsOf format.type;
      default = {
        uptime.prefix = "Up";
        service_status.nginx = "nginx";
        filesystems.root = "/";
        last_login.gquetel = 3;
        filesystems.boot = "/boot";
        memory.swap_pos = "none";
        fail_2_ban.jails = [ "sshd" ];
      };
    };
  };

  config = mkIf cfgmotd.enable {
    programs.rust-motd = {
      enable = true;
      order = cfgmotd.order;
      settings = cfgmotd.settings;
    };
    systemd.services.rust-motd.path = [ pkgs.fail2ban ];
  };

}
