
# Appended to hermes' hermes_cli/gateway.py.
#
# Hermes owns /etc/systemd/system/hermes-gateway.service on a normal install:
# it compares the file against its own template on every status/restart and
# rewrites it when they differ. On NixOS the unit is a read-only store
# symlink, so `hermes gateway restart` dies with EROFS and `status` reports
# the unit as permanently outdated. It also refuses system-scope actions
# unless euid is 0, which blocks the dashboard's restart button.
#
# Active only when HERMES_NIXOS_UNIT is set, so an interactive `hermes` run
# outside the units keeps upstream behaviour. Authorization for the plain
# `systemctl restart` still applies; the polkit rule in modules/hermes grants
# it to the service user.
import os as _nix_os


def _nixos_managed_unit() -> bool:
    return bool(_nix_os.environ.get("HERMES_NIXOS_UNIT"))


_nixos_unit_is_current = systemd_unit_is_current
_nixos_refresh_unit = refresh_systemd_unit_if_needed
_nixos_require_root = _require_root_for_system_service


def systemd_unit_is_current(system: bool = False) -> bool:
    if _nixos_managed_unit():
        return True
    return _nixos_unit_is_current(system=system)


def refresh_systemd_unit_if_needed(system: bool = False) -> bool:
    if _nixos_managed_unit():
        return False
    return _nixos_refresh_unit(system=system)


def _require_root_for_system_service(action: str) -> None:
    if _nixos_managed_unit():
        return
    _nixos_require_root(action)
