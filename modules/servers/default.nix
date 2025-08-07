{
  lib,
  config,
  pkgs,
  ...
}:
{

  # https://discourse.nixos.org/t/alternative-to-salt-grains-or-puppet-facts/3308/4
  # motd replacement.
  environment.loginShellInit = ''
    if [ `id -u` != 0 ]; then                                                                                                        
      if [ "x''${SSH_TTY}" != "x" ]; then                                                                                            
        echo "[ Hostname: $(hostname) ]"
        echo "[ Kernel: $(uname -r) ]"
        echo "[ Disk Usage: $(df -h / | tail -1 | awk '{print $5 " used of " $2}') ]"
        failed=$(systemctl --failed --no-legend --plain | awk '{print $1}')
        if [ -n "$failed" ]; then
          echo "[ Failed Services: $failed ]"
        else
          echo "[ All systemd services OK ]"
        fi                                                                                                
      fi                                                                                                                             
    fi                                                                                                                               
  '';

  environment.systemPackages = [
    pkgs.sysstat
  ];
}
