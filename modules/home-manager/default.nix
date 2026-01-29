{
  lib,
  config,
  nodes,
  ...
}:

with lib;

let
  cfg = config.hm;
in
{
  options.hm = {
    enable = mkEnableOption "Enable home-manager on this machine";
  };

  config = mkIf cfg.enable {
    # use the global pkgs that is configured via the system level nixpkgs options
    home-manager.useGlobalPkgs = true;

    home-manager.users.gquetel =
      { pkgs, ... }:
      {
        home.packages =
          with pkgs;
          [
            black
            drawio
            element-desktop
            intel-gpu-tools
            nix-init
            nixfmt
            obsidian
            openvpn
            signal-desktop
            spotify
            tex-fmt # TODO keep ?
            texliveFull
            thunderbird
            tinymist
            treefmt
            typst
            typstyle
            unstable.claude-code
            vlc
            zoom-us
            zotero
          ]
          ++ [
            (pkgs.callPackage "${(import ../../npins).agenix}/pkgs/agenix.nix" { })
          ];
        programs.kitty = {
          enable = true;
          # Use names from: https://github.com/kovidgoyal/kitty-themes/tree/master/themes
          # TODO: Have something that looks similar to  vscode theme.
          themeFile = "Seafoam_Pastel";
          keybindings = {
            "ctrl+shift+t" = "new_tab_with_cwd";
          };
        };
        # https://discourse.nixos.org/t/nixos-options-to-configure-gnome-keyboard-shortcuts/7275/4
        dconf.settings = {
          "org/gnome/settings-daemon/plugins/media-keys" = {
            custom-keybindings = [
              "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
            ];
          };
          "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
            binding = "<Primary><Alt>t";
            command = "kitty";
            name = "open-terminal";
          };
        };

        # Let Home Manager install and manage itself.
        programs.home-manager.enable = true;

        programs.git = {
          enable = true;
          userName = "gquetel";
          userEmail = "quetel.gregor@gmail.com";

          extraConfig = {
            init = {
              defaultBranch = "main";
            };
            pull.rebase = true;
            rebase.autoStash = true;
            # Prevents from using the HTTP version of a repo.
            "url \"github.com:\"".pushInsteadOf = "https://github.com";

            # Display more information about submodules on git status.
            status.submoduleSummary = true;
            diff.submodule = "log";

            # This causes most operations, like git checkout, fetch, pull, push, etc. to automatically recurse into submodules.
            submodule.recurse = true;
          };
        };

        programs.vscode = {
          enable = true;
          # We force declarative extension installation.
          mutableExtensionsDir = false;

          profiles.default = {
            # Disable update notification for extensions.
            enableExtensionUpdateCheck = false;
            # TODO
            # Integrate MCP server config
            enableMcpIntegration = true;
            extensions =
              with pkgs.vscode-extensions;
              [
                daohong-emilio.yash
                github.copilot-chat
                github.vscode-github-actions
                james-yu.latex-workshop
                jnoortheen.nix-ide
                mechatroner.rainbow-csv
                ms-python.black-formatter
                ms-python.python
                ms-python.vscode-pylance
                ms-toolsai.jupyter
                ms-toolsai.jupyter-renderers
                ms-vscode-remote.remote-ssh
                ms-vscode.cpptools
                myriad-dreamin.tinymist
                njpwerner.autodocstring
                redhat.vscode-yaml
                tamasfe.even-better-toml
                valentjn.vscode-ltex
                yzhang.markdown-all-in-one
              ]
              ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace ([
                {
                  name = "vscode-edit-csv";
                  publisher = "janisdd";
                  hash = "sha256-Wr3zHz5MfI52YEZHjnB/4Cy+QWl19W8yxoe9eJjbeco=";
                  version = "0.11.8";
                }
                {
                  name = "sand-theme";
                  publisher = "dhrumil";
                  hash = "sha256-6rGOyUtRqjxMBZSG+npOcZnmafIz8uQbyr0+qJW5T34=";
                  version = "0.1.0";
                }
                {
                  name = "claude-code";
                  publisher = "anthropic";
                  version = "2.1.11";
                  sha256 = "sha256-WYl3XezAaasLvMVwbVE/+WwwYJHk8BD7rQBXwdPXe8c=";
                }
              ]);
          };

          userSettings = {
            "editor.minimap.enabled" = false;
            "black-formatter.args" = [
              "--line-length=85"
            ];
            "editor.rulers" = [
              85
            ];
            "redhat.telemetry.enabled" = false;
            "[typst]" = {
              "editor.wordSeparators" = "`~!@#$%^&*()=+[{]}\\|;:'\",.<>/?";
              "editor.wordWrap" = "bounded";
            };
            "[typst-code]" = {
              "editor.wordSeparators" = "`~!@#$%^&*()=+[{]}\\|;:'\",.<>/?";
            };
            "workbench.colorTheme" = "Sand (Light)";
            "[python]" = {
              "editor.defaultFormatter" = "ms-python.black-formatter";
              "editor.wordWrap" = "off";
              "editor.wordWrapColumn" = 90;
            };
            "notebook.output.textLineLimit" = 90;
            "latex-workshop.latex.autoBuild.run" = "onSave";
            "window.customTitleBarVisibility" = "windowed";
            "github.copilot.enable" = {
              "*" = false;
            };
            "git.openRepositoryInParentFolders" = "never";
            "python.defaultInterpreterPath" = "\${CUSTOM_INTERPRETER_PATH}";
            "latex-workshop.formatting.latex" = "tex-fmt";
            "[csv]" = {
              "editor.wordWrap" = "on";
            };
            "[tex]" = {
              "editor.wordWrap" = "bounded";
            };
            "[latex]" = {
              "editor.wordWrap" = "off";
              "editor.wordWrapColumn" = 90;
            };
            "terminal.integrated.fontFamily" = "monospace";
            "latex-workshop.latex.outDir" = "%DIR%/output";
            "ltex.language" = "en-GB";
            "ltex.languageToolHttpServerUri" = "http://localhost:8787/";
            "github.copilot.nextEditSuggestions.enabled" = true;
            "editor.wordWrapColumn" = 90;
            "editor.wordWrap" = "bounded";
            "editor.fontFamily" = "'Hack', 'Droid Sans Mono', 'monospace', monospace";
          };
        };

        # The state version is required and should stay at the version you
        # originally installed.
        home.stateVersion = "25.11";
      };
  };
}
