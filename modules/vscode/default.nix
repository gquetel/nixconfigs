{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.vscode;
  unstable = pkgs.unstable;
in
{
  options = {
    vscode.enable = lib.mkEnableOption "Install custom vscode with development extensions.";
    vscode.user = lib.mkOption {
      type = lib.types.str;
      default = "gquetel";
      description = "Username to install VSCode for";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      packages = lib.mkIf (config.users.users ? ${cfg.user}) ([
        (unstable.vscode-with-extensions.override {
          vscodeExtensions =
            with unstable.vscode-extensions;
            [
              bbenoist.nix
              daohong-emilio.yash
              github.copilot
              james-yu.latex-workshop
              jnoortheen.nix-ide
              mechatroner.rainbow-csv
              ms-python.black-formatter
              # ms-python.python
              ms-python.vscode-pylance
              ms-toolsai.jupyter
              ms-toolsai.jupyter-renderers
              ms-vscode.cpptools
              myriad-dreamin.tinymist
              njpwerner.autodocstring
              redhat.vscode-yaml
              visualstudioexptteam.vscodeintellicode
              yzhang.markdown-all-in-one
            ]
            ++ unstable.vscode-utils.extensionsFromVscodeMarketplace ([
              {
                # https://github.com/NixOS/nixpkgs/pull/387839/commits/4886e147e1b285057228cbd7ce2348cf8fb4cb45
                # Manual change until hash mismatch is fixed in unstable.
                name = "python";
                publisher = "ms-python";
                hash = "sha256-f573A/7s8jVfH1f3ZYZSTftrfBs6iyMWewhorX4Z0Nc=";
                version = "2025.2.0";
              }
              {
                name = "vscode-edit-csv";
                publisher = "janisdd";
                hash = "sha256-xMZSzbRbG3OCWhTBusx06i0XoN81feNDfOmF1hezmZg=";
                version = "0.11.2";
              }
              { # vscode-extensions.ms-vscode-remote, usntable version fails to connect to TP clusters on hydra.
                name = "remote-ssh";
                publisher = "ms-vscode-remote";
                hash = "sha256-vd+9d86Z8429QpQVCZm8gtiJDcMpD++aiFVwvCrPg5w=";
                version = "0.78.0";
              }
            ]);
        })
      ]);
    };
  };
}
