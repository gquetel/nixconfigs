{
  lib,
  config,
  pkgs,
  ...
}:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile ./interactive_init.fish;
    shellAliases = {
      v6 = "curl api6.ipify.org";
      v4 = "curl api.ipify.org";
      nsp = "nix-shell -p";
      ns = "nix-shell";
      nb = "nix-build";
      ncg = "sudo nix-collect-garbage --delete-older-than 30d";
      nsc = "nix-shell --command \"code . ; return\"";
      nsf = "nix-shell --run fish";
      nspf = "nix-shell --run fish -p";
      nscf = "nix-shell --command \"fish; code . ; return\"";

      c = "code .";
      rgf = "rg --files | rg";

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

}
