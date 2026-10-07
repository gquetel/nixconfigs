{ ... }:
{
  # motd. Hosts add their sections, e.g. `programs.rust-motd.settings.service_status`.
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
      "global"
    ];
    settings = {
      uptime.prefix = "Up";
      service_status.nginx = "nginx";
      filesystems.root = "/";
      filesystems.boot = "/boot";
      last_login.gquetel = 3;
      memory.swap_pos = "none";
      fail_2_ban.jails = [
        "sshd"
        "nginx-404-scan"
      ];
    };
  };
}
