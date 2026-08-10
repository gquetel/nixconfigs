{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.mullvad;

  netnsPath = "/run/netns/${cfg.netns}";
  unit = "mullvad-netns.service";

  secretFile = ../../secrets/mullvad-pvkey.age;

  resolvConf = pkgs.writeText "mullvad-resolv.conf" (
    concatMapStrings (a: "nameserver ${a}\n") cfg.dns
  );

  resolvTarget =
    if config.services.resolved.enable then
      "/run/systemd/resolve/stub-resolv.conf"
    else
      "/etc/resolv.conf";

  setup = pkgs.writeShellScript "mullvad-netns-up" ''
    set -euo pipefail
    export PATH=${
      makeBinPath [
        pkgs.iproute2
        pkgs.wireguard-tools
      ]
    }

    . ${config.age.secrets.mullvad.path}

    if [ -z "''${PRIVATE_KEY:-}" ] || [ -z "''${ADDRESS:-}" ]; then
      echo "mullvad-pvkey.age must define PRIVATE_KEY= and ADDRESS=; see secrets/secrets.nix" >&2
      exit 1
    fi

    ip netns del ${cfg.netns} 2>/dev/null || true
    ip link del ${cfg.interface} 2>/dev/null || true

    ip netns add ${cfg.netns}
    ip link add ${cfg.interface} type wireguard

    wg set ${cfg.interface} \
      private-key <(printf '%s' "$PRIVATE_KEY") \
      peer ${cfg.publicKey} \
      endpoint ${cfg.endpoint} \
      persistent-keepalive 25 \
      allowed-ips 0.0.0.0/0,::/0

    ip link set ${cfg.interface} netns ${cfg.netns}
    ip -n ${cfg.netns} link set lo up

    have6=0
    IFS=',' read -ra addrs <<< "$ADDRESS"
    for a in "''${addrs[@]}"; do
      a="''${a// /}"
      if [ -z "$a" ]; then continue; fi
      ip -n ${cfg.netns} addr add "$a" dev ${cfg.interface}
      case "$a" in *:*) have6=1 ;; esac
    done

    ip -n ${cfg.netns} link set ${cfg.interface} up

    ip -n ${cfg.netns} route add default dev ${cfg.interface}
    if [ "$have6" = 1 ]; then
      ip -n ${cfg.netns} -6 route add default dev ${cfg.interface}
    fi
  '';

  teardown = pkgs.writeShellScript "mullvad-netns-down" ''
    ${pkgs.iproute2}/bin/ip netns del ${cfg.netns} 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link del ${cfg.interface} 2>/dev/null || true
  '';
in
{
  options.mullvad = {
    enable = mkEnableOption "Mullvad WireGuard tunnel in its own network namespace";

    netns = mkOption {
      type = types.str;
      default = "mullvad";
      description = "Name of the network namespace holding the tunnel.";
    };

    interface = mkOption {
      type = types.str;
      default = "mullvad0";
      description = "Name of the tunnel interface inside the namespace.";
    };

    publicKey = mkOption {
      type = types.str;
      description = "Public key of the Mullvad server to connect to.";
    };

    endpoint = mkOption {
      type = types.str;
      example = "se-mma-wg-001.relays.mullvad.net:51820";
      description = "Host:port of the Mullvad server to connect to.";
    };

    dns = mkOption {
      type = types.listOf types.str;
      default = [ "10.64.0.1" ];
      description = ''
        Mullvad's in-tunnel resolvers. Do not use the content-blocking
        variants on 100.64.0.0/10: that range is Tailscale's here.
      '';
    };

    proxies = mkOption {
      default = { };
      description = ''
        TCP forwards from the host into the namespace, so services outside it
        can still reach a confined one at its usual address.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            listen = mkOption {
              type = types.str;
              example = "127.0.0.1:58846";
              description = "Address to accept connections on, in the root namespace.";
            };
            connect = mkOption {
              type = types.str;
              example = "127.0.0.1:58846";
              description = "Address to forward them to, inside the namespace.";
            };
          };
        }
      );
    };

    confine = mkOption {
      type = types.attrs;
      readOnly = true;
      default = optionalAttrs cfg.enable {
        bindsTo = [ unit ];
        partOf = [ unit ];
        after = [ unit ];
        serviceConfig = {
          NetworkNamespacePath = netnsPath;
          BindReadOnlyPaths = [ "${resolvConf}:${resolvTarget}" ];
          InaccessiblePaths = [
            "-/run/nscd"
            "-/run/systemd/resolve/io.systemd.Resolve"
          ];
        };
      };
      defaultText = literalMD "unit fragment binding a service to the namespace";
      description = ''
        systemd unit fragment moving a service into the namespace and pointing
        it at the tunnel's resolver, e.g.
        `systemd.services.foo = config.mullvad.confine;`. Empty when disabled.
      '';
    };
  };

  config = mkIf cfg.enable {
    age.secrets.mullvad.file = secretFile;

    systemd.sockets = mapAttrs' (
      name: p:
      nameValuePair "mullvad-proxy-${name}" {
        description = "Socket for ${name}, forwarded into the Mullvad namespace";
        wantedBy = [ "sockets.target" ];
        socketConfig.ListenStream = p.listen;
      }
    ) cfg.proxies;

    systemd.services = {
      mullvad-netns = {
        description = "Mullvad WireGuard network namespace";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = setup;
          ExecStop = teardown;
        };
      };
    }
    
    // mapAttrs' (
      name: p:
      nameValuePair "mullvad-proxy-${name}" {
        description = "Forward ${p.listen} into the Mullvad namespace";
        requires = [ "mullvad-proxy-${name}.socket" ];
        bindsTo = [ unit ];
        partOf = [ unit ];
        after = [
          "mullvad-proxy-${name}.socket"
          unit
        ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${p.connect}";
          NetworkNamespacePath = netnsPath;
          DynamicUser = true;
        };
      }
    ) cfg.proxies;
  };
}
