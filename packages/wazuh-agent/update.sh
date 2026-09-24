#!/usr/bin/env bash
# Pin one Wazuh release for the whole cluster: the agent sources
# (packages/wazuh-agent/sources.json) and the manager image
# (modules/wazuh-manager/image.json).
#
# Usage: packages/wazuh-agent/update.sh <version>, e.g. 4.14.8
# Needs curl, git and nix. Deploy the manager (garmr) before the agents.
set -euo pipefail

version=${1:?usage: $0 <version>}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)

prefetch() {
  nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --type sha256 "$@" 2>/dev/null)"
}

makefile=$(curl -sfL "https://raw.githubusercontent.com/wazuh/wazuh/v$version/src/Makefile")
deps_version=$(sed -n 's/^DEPS_VERSION = //p' <<<"$makefile")
http_request_rev=$(sed -n 's/^HTTP_REQUEST_BRANCH?=//p' <<<"$makefile")
# The first EXTERNAL_RES line is the agent set. Later lines add manager deps.
deps=$(sed -n 's/^EXTERNAL_RES := //p' <<<"$makefile")
vmlinux_rev=$(git ls-remote https://github.com/libbpf/vmlinux.h refs/heads/main | cut -f1)

echo "wazuh $version: DEPS_VERSION=$deps_version, $(wc -w <<<"$deps") deps" >&2

{
  printf '{\n'
  printf '  "version": "%s",\n' "$version"
  printf '  "hash": "%s",\n' "$(prefetch --unpack "https://github.com/wazuh/wazuh/archive/v$version.tar.gz")"
  printf '  "depsVersion": "%s",\n' "$deps_version"
  printf '  "httpRequest": { "rev": "%s", "hash": "%s" },\n' "$http_request_rev" \
    "$(prefetch --unpack "https://github.com/wazuh/wazuh-http-request/archive/$http_request_rev.tar.gz")"
  printf '  "vmlinux": { "rev": "%s", "hash": "%s" },\n' "$vmlinux_rev" \
    "$(prefetch --unpack "https://github.com/libbpf/vmlinux.h/archive/$vmlinux_rev.tar.gz")"
  printf '  "deps": {\n'
  sep=""
  for dep in $deps; do
    printf '%s    "%s": "%s"' "$sep" "$dep" \
      "$(prefetch "https://packages.wazuh.com/deps/$deps_version/libraries/sources/$dep.tar.gz")"
    sep=$',\n'
  done
  printf '\n  }\n}\n'
} >"$here/sources.json.new"
mv "$here/sources.json.new" "$here/sources.json"

# Digest of the multi-arch index, so podman pulls exactly this image.
token=$(curl -sf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:wazuh/wazuh-manager:pull" |
  sed -E 's/.*"token":"([^"]+)".*/\1/')
digest=$(curl -sfI -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://registry-1.docker.io/v2/wazuh/wazuh-manager/manifests/$version" |
  sed -n 's/^docker-content-digest: *//Ip' | tr -d '\r')
printf '{\n  "version": "%s",\n  "digest": "%s",\n  "configHash": "%s"\n}\n' "$version" "$digest" \
  "$(prefetch "https://raw.githubusercontent.com/wazuh/wazuh-docker/v$version/single-node/config/wazuh_cluster/wazuh_manager.conf")" \
  >"$repo/modules/wazuh-manager/image.json"

echo "Updated sources.json and image.json to $version." >&2
