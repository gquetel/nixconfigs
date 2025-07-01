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
  };

  # Required by fail2ban
  services.openssh.settings.LogLevel = "VERBOSE"; 
}
