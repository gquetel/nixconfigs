{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.outline-export;
  outline-export = pkgs.callPackage ./package.nix { };
in
{
  options.services.outline-export = {
    enable = mkEnableOption "periodic Outline wiki export";

    url = mkOption {
      type = types.str;
      description = "URL of the Outline instance.";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "Path to a file containing the Outline API token.";
    };

    exportPath = mkOption {
      type = types.str;
      description = "Directory where exports are stored.";
    };

    format = mkOption {
      type = types.enum [
        "markdown"
        "html"
        "json"
      ];
      default = "markdown";
      description = "Export format.";
    };

    extract = mkOption {
      type = types.bool;
      default = true;
      description = "Extract the zip archive into the export directory.";
    };

    excludeAttachments = mkOption {
      type = types.bool;
      default = false;
      description = "Omit media/attachment files from the export.";
    };

    excludePrivate = mkOption {
      type = types.bool;
      default = false;
      description = "Omit private collections from the export.";
    };

    interval = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the export timer.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.outline-export = {
      description = "Export Outline wiki collections";
      after = [ "tailscale-online.service" ];

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "outline-export";
        EnvironmentFile = cfg.tokenFile;

        ExecStart =
          let
            flags = [
              "--url ${cfg.url}"
              "--format ${cfg.format}"
              "--export-path ${cfg.exportPath}"
            ]
            ++ optional cfg.extract "--extract"
            ++ optional cfg.excludeAttachments "--exclude-attachments"
            ++ optional cfg.excludePrivate "--exclude-private";
          in
          "${outline-export}/bin/outline-export ${concatStringsSep " " flags}";

        # Sandbox hardening
        ReadWritePaths = [ cfg.exportPath ];
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.outline-export = {
      description = "Timer for Outline wiki export";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };
}
