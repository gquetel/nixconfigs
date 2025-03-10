{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.fish;
  unstable = pkgs.unstable;
in
{
  options = {
    fish.enable = lib.mkEnableOption "Install custom fish environment.";
  };

  config = lib.mkIf cfg.enable {
    
    programs.fish = {
      enable = true;
      interactiveShellInit = builtins.readFile ./interactive_init.fish;
      shellAliases = {
        v6 = "curl api6.ipify.org";
        v4 = "curl api.ipify.org";
        nsp = "nix-shell -p";
        ns = "nix-shell";
        ncg = "sudo nix-collect-garbage --delete-older-than 30d";
      };
    };

    programs.bash = {
      interactiveShellInit = ''
        if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
        then
          shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
          exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
        fi
      '';
    };
  };
}
