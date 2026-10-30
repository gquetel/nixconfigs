{
  config,
  lib,
  pkgs,
  ...
}:
# Runtime for the hda-bot reel generator, driven by Hermes over MCP.
#
# This module does not package the app. `hda-mcp` clones or pulls
# gquetel/hda-bot into /var/lib/hda/app on start and runs it from there.
# Hermes calls it as /run/current-system/sw/bin/hda-mcp (mcp_servers.HDA in
# ~/.hermes/config.yaml).
let
  cfg = config.hda;
  stateDir = "/var/lib/hda";
  appDir = "${stateDir}/app";

  user = config.hermes.user;
  group = config.users.users.${user}.group;

  # Same packages as the app's shell.nix.
  python = pkgs.python3.withPackages (ps: [
    ps.pyvips
    ps.numpy
    ps.httpx
    ps.pyyaml
    ps.mcp
    ps.num2words
  ]);

  runtimeInputs = [
    python
    pkgs.ffmpeg-headless
    pkgs.whisper-cpp
    # Creates the TTS venv (torch + moshi from PyPI) on first use.
    pkgs.uv
  ];

  env = ''
    export HDA_STATE_DIR=${stateDir}
    export PYTHONPATH=${appDir}/src
    # The TTS venv's pip wheels need these on NixOS.
    export HDA_TTS_LIBS=${
      lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.zlib
      ]
    }
  '';

  # stdout is the MCP channel, so git output goes to stderr.
  hda-mcp = pkgs.writeShellApplication {
    name = "hda-mcp";
    runtimeInputs = runtimeInputs ++ [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      ${env}
      if [ -d ${appDir}/.git ]; then
        git -C ${appDir} pull --ff-only >&2 || echo "hda-mcp: pull failed, using current checkout" >&2
      else
        git clone ${cfg.repo} ${appDir} >&2
      fi
      exec python -m hda.mcp_server
    '';
  };

  hda = pkgs.writeShellApplication {
    name = "hda";
    inherit runtimeInputs;
    text = ''
      ${env}
      exec python -m hda.cli "$@"
    '';
  };

  skills = [
    "hda-story"
    "hda-reels"
    "hda-review"
  ];
in
{
  options.hda = with lib; {
    enable = mkEnableOption "hda-bot runtime (hda-mcp and hda commands)";

    repo = mkOption {
      type = types.str;
      default = "git@github.com:gquetel/hda-bot.git";
      description = "Git URL that hda-mcp clones into ${appDir}.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hermes.enable;
        message = "hda requires hermes.enable: Hermes spawns hda-mcp.";
      }
    ];

    environment.systemPackages = [
      hda-mcp
      hda
    ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${user} ${group} -"
      "e ${stateDir}/candidates - - - 7d"
      "e ${stateDir}/cache - - - 90d"
    ]
    # Hermes loads the app's skills from its own skills directory.
    ++ map (
      s: "L+ ${config.users.users.${user}.home}/.hermes/skills/${s} - - - - ${appDir}/hermes/skills/${s}"
    ) skills;
  };
}
