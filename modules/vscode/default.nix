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

  # TODO: Replace gquetel by something else ? Option ?
  users.users.gquetel = {
    packages = ([
      (pkgs.vscode-with-extensions.override {
        vscodeExtensions =
          with pkgs.vscode-extensions;
          [
            bbenoist.nix
            daohong-emilio.yash
            james-yu.latex-workshop
            jnoortheen.nix-ide
            mechatroner.rainbow-csv
            ms-python.black-formatter
            ms-python.python
            ms-python.vscode-pylance
            ms-toolsai.jupyter
            ms-toolsai.jupyter-renderers
            ms-vscode.cpptools
            myriad-dreamin.tinymist
            njpwerner.autodocstring
            redhat.vscode-yaml
            valentjn.vscode-ltex
            visualstudioexptteam.vscodeintellicode
            yzhang.markdown-all-in-one
            github.vscode-github-actions
          ]
          ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace ([
            {
              name = "vscode-edit-csv";
              publisher = "janisdd";
              hash = "sha256-xMZSzbRbG3OCWhTBusx06i0XoN81feNDfOmF1hezmZg=";
              version = "0.11.2";
            }
            {
              # vscode-extensions.ms-vscode-remote, usntable version fails to connect to TP clusters on hydra.
              name = "remote-ssh";
              publisher = "ms-vscode-remote";
              hash = "sha256-vd+9d86Z8429QpQVCZm8gtiJDcMpD++aiFVwvCrPg5w=";
              version = "0.78.0";
            }
          ]);
      })
    ]);

  };
}
