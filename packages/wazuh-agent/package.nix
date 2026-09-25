{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  autoconf,
  automake,
  bpftools,
  cmake,
  expat,
  fakeroot,
  libbpf,
  libtool,
  llvmPackages,
  perl,
  pkg-config,
  procps,
  python3,
  systemd,
}:
# Wazuh agent (https://wazuh.com), built from source with the upstream
# Makefile and installed with the upstream install.sh.
# All pins are in sources.json. To upgrade, run ./update.sh <version>.
let
  sources = lib.importJSON ./sources.json;

  deps = lib.mapAttrsToList (
    name: hash:
    fetchurl {
      url = "https://packages.wazuh.com/deps/${sources.depsVersion}/libraries/sources/${name}.tar.gz";
      inherit hash;
    }
  ) sources.deps;

  httpRequest = fetchFromGitHub {
    owner = "wazuh";
    repo = "wazuh-http-request";
    inherit (sources.httpRequest) rev hash;
  };

  vmlinux = fetchFromGitHub {
    owner = "libbpf";
    repo = "vmlinux.h";
    inherit (sources.vmlinux) rev hash;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wazuh-agent";
  inherit (sources) version;

  src = fetchFromGitHub {
    owner = "wazuh";
    repo = "wazuh";
    tag = "v${finalAttrs.version}";
    inherit (sources) hash;
  };

  nativeBuildInputs = [
    autoconf
    automake
    bpftools
    cmake
    fakeroot
    libtool
    perl
    pkg-config
    python3
  ];

  buildInputs = [
    expat
  ];

  # The top-level CMakeLists.txt files belong to the upstream Makefile.
  dontUseCmakeConfigure = true;

  postUnpack = ''
    mkdir -p "$sourceRoot/src/external"
    for dep in ${toString deps}; do
      tar -xzf "$dep" -C "$sourceRoot/src/external"
    done
    cp -r --no-preserve=mode ${httpRequest}/. "$sourceRoot/src/shared_modules/http-request"
    patchShebangs "$sourceRoot/src/external"
  '';

  postPatch = ''
    substituteInPlace \
      src/rootcheck/unix-process.c \
      src/rootcheck/check_rc_pids.c \
      src/shared/os_utils.c \
      --replace-fail '"/bin/ps"' '"${procps}/bin/ps"' \
      --replace-fail '"/usr/bin/ps"' '"${procps}/bin/ps"'

    # Dependencies that the upstream Makefile does not declare:
    # - libalpm includes headers that the OpenSSL build generates.
    # - sysinfo (inventory) links the vendored libdb, which the agent target
    #   does not build.
    cat >> src/Makefile <<'EOF'
    $(LIBALPM_LIB): $(OPENSSL_LIB)
    external: $(DB_LIB)
    EOF

    # autoreconf installs INSTALL read-only from the store, then autogen.sh
    # copies over it.
    substituteInPlace src/external/audit-userspace/autogen.sh \
      --replace-fail 'cp INSTALL.tmp INSTALL' 'cp -f INSTALL.tmp INSTALL'

    # install.sh sets owners to root and wazuh. fakeroot accepts root only.
    substituteInPlace src/init/inst-functions.sh \
      --replace-fail "WAZUH_GROUP='wazuh'" "WAZUH_GROUP='root'" \
      --replace-fail "WAZUH_USER='wazuh'" "WAZUH_USER='root'"
  '';

  env.NIX_CFLAGS_COMPILE = toString [
    "-Wno-error=incompatible-pointer-types"
    "-Wno-error=implicit-function-declaration"
    "-Wno-error=int-conversion"
  ];

  makeFlags = [
    "-C"
    "src"
    "TARGET=agent"
    "INSTALLDIR=${placeholder "out"}"
    # Use only the sources in src/external, never precompiled downloads.
    "EXTERNAL_SRC_ONLY=yes"
    # The Makefile strips copies of read-only store libraries. The fixup
    # phase strips the output.
    "STRIP_TOOL=true"
  ];
  buildFlags = [ "build" ];
  enableParallelBuilding = true;

  # The vendored libbpf-bootstrap build clones libbpf, bpftool and vmlinux.h.
  # Make its two outputs here with the nixpkgs tools, so the Makefile skips it.
  preBuild = ''
    bpf=src/external/libbpf-bootstrap/build
    mkdir -p $bpf/libbpf
    ${lib.getExe' llvmPackages.clang-unwrapped "clang"} -g -O2 -target bpf -D__TARGET_ARCH_x86 \
      -I${vmlinux}/include/x86 -isystem ${lib.getDev libbpf}/include \
      -c src/syscheckd/src/ebpf/src/modern.bpf.c -o $bpf/modern.bpf.o
    bpftool gen skeleton $bpf/modern.bpf.o > $bpf/modern.skel.h
    # Same edit as the upstream CMake file: the agent loads libbpf with dlopen.
    sed -i 's|<bpf/libbpf.h>|"wrapper_bpf.h"|' $bpf/modern.skel.h
    cp -L ${lib.getLib libbpf}/lib/libbpf.so $bpf/libbpf/libbpf.so
  '';

  installPhase = ''
    runHook preInstall

    cat > etc/preloaded-vars.conf <<EOF
    USER_LANGUAGE="en"
    USER_NO_STOP="y"
    USER_INSTALL_TYPE="agent"
    USER_DIR="$out"
    USER_DELETE_DIR="n"
    USER_ENABLE_ACTIVE_RESPONSE="n"
    USER_ENABLE_SYSCHECK="y"
    USER_ENABLE_ROOTCHECK="y"
    USER_AGENT_SERVER_IP="127.0.0.1"
    USER_CA_STORE="n"
    USER_AUTO_START="n"
    EOF
    fakeroot ./install.sh binary-install

    runHook postInstall
  '';

  # install.sh copies the CMake libraries from their build directories, and
  # their RPATH still points there. Point it to the installed lib/ instead.
  preFixup = ''
    for f in $out/bin/* $out/lib/*.so*; do
      isELF "$f" || continue
      case "$f" in
        $out/bin/*) origin='$ORIGIN/../lib' ;;
        *) origin='$ORIGIN' ;;
      esac
      rpath=$(patchelf --print-rpath "$f" | tr ':' '\n' \
        | sed "s|^$NIX_BUILD_TOP/.*|$origin|" | awk 'NF && !seen[$0]++' | paste -sd:)
      patchelf --set-rpath "$rpath" "$f"
    done
  '';

  # logcollector loads libsystemd with dlopen to read the journal. After the
  # fixup phase, which removes RPATH entries that no linked library uses.
  postFixup = ''
    patchelf --add-rpath ${lib.getLib systemd}/lib $out/bin/wazuh-logcollector
  '';

  meta = {
    description = "Wazuh security agent: log collection, file integrity and inventory";
    homepage = "https://wazuh.com";
    changelog = "https://github.com/wazuh/wazuh/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl2Only;
    # The eBPF object is built for x86 only.
    platforms = [ "x86_64-linux" ];
    mainProgram = "wazuh-agentd";
  };
})
