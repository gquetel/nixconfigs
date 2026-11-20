# Custom backup wrapper: we provide it so that every host gets the same restic
# job (repository, schedule, retention, check...). Then modules can use this as
# follows to backup any content using that policy:
#
#   backup.paths = [ "/var/lib/outline" ];
#   backup.exclude = [ "/var/lib/outline/data/uploads/*/*/*-export.*.zip" ];
#   backup.postgresDatabases = [ "outline" ];
#
# and the host turns it on with `backup.enable = true;`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.backup;
  host = config.networking.hostName;
  dumpDir = "/var/backup/restic";
  hasDatabases = cfg.postgresDatabases != [ ];

  # Uncompressed custom-format dumps, so restic deduplicates and compresses them.
  dumpDatabases = pkgs.writeShellScript "backup-dump-postgres" ''
    set -euo pipefail
    umask 0077
    mkdir -p ${dumpDir}
    ${lib.concatMapStrings (db: ''
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dump --format=custom --compress=0 ${lib.escapeShellArg db} \
        > ${dumpDir}/${lib.escapeShellArg db}.dump
    '') cfg.postgresDatabases}
  '';
in
{
  options.backup = {
    enable = lib.mkEnableOption "daily restic backup to the Garage bucket restic-<hostname> on fafnir";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up. Service modules should provide here their state directories.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Restic exclude patterns.";
    };

    postgresDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Local PostgreSQL databases dumped before each backup, as live data files cannot be copied safely.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.paths != [ ] || hasDatabases;
        message = "backup.enable requires backup.paths or backup.postgresDatabases.";
      }
    ];

    age.secrets."restic-${host}.pwd".file = ../../secrets + "/restic-${host}.pwd.age";
    age.secrets."restic-${host}.env".file = ../../secrets + "/restic-${host}.env.age";

    services.restic.backups.offsite = {
      repository = "s3:https://s3.gquetel.fr/restic-${host}";
      passwordFile = config.age.secrets."restic-${host}.pwd".path;
      environmentFile = config.age.secrets."restic-${host}.env".path;
      initialize = true;
      extraOptions = [
        "s3.bucket-lookup=path"
        "s3.region=garage"
      ];
      paths = cfg.paths ++ lib.optional hasDatabases dumpDir;
      inherit (cfg) exclude;
      backupPrepareCommand = lib.mkIf hasDatabases "${dumpDatabases}";
      backupCleanupCommand = lib.mkIf hasDatabases "${pkgs.coreutils}/bin/rm -rf ${dumpDir}";
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "30min";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
      checkOpts = [ "--read-data-subset=5%" ];
    };

    systemd.services.restic-backups-offsite = {
      requires = lib.optional hasDatabases "postgresql.target";
      after = lib.optional hasDatabases "postgresql.target";
    };
  };
}
