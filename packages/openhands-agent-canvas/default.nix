{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
  uv,
  python3,
  zlib,
}:
# Agent Canvas, the OpenHands UI. The npm tarball ships the pre-built frontend
# (build/) and the launcher scripts; only two runtime deps are missing from it,
# so node_modules is assembled by hand instead of going through
# buildNpmPackage (upstream publishes no lockfile).
#
# The Python half (agent-server, automation) is not packaged here: the launcher
# fetches it with uvx at first start, pinned to the versions in
# config/defaults.json.
let
  version = "1.9.0";

  # Bare imports in bin/ and scripts/, plus sirv's own dependencies.
  deps = {
    "httpxy" = fetchurl {
      url = "https://registry.npmjs.org/httpxy/-/httpxy-0.5.3.tgz";
      hash = "sha512-SMS9V6Sn7VWaS11lYhoAr0ceoaiolTWf4jYdJn0NJhCdKMu9R2H9Fh0LBDWBHQF6HRLI1PmaePYsjanSpE5PEw==";
    };
    "sirv" = fetchurl {
      url = "https://registry.npmjs.org/sirv/-/sirv-3.0.2.tgz";
      hash = "sha512-2wcC/oGxHis/BoHkkPwldgiPSYcpZK3JU28WoMVv55yHJgcZ8rlXvuG9iZggz+sU1d4bRgIGASwyWqjxu3FM0g==";
    };
    "mrmime" = fetchurl {
      url = "https://registry.npmjs.org/mrmime/-/mrmime-2.0.1.tgz";
      hash = "sha512-Y3wQdFg2Va6etvQ5I82yUhGdsKrcYox6p7FfL1LbK2J4V01F9TGlepTIhnK24t7koZibmg82KGglhA1XK5IsLQ==";
    };
    "totalist" = fetchurl {
      url = "https://registry.npmjs.org/totalist/-/totalist-3.0.1.tgz";
      hash = "sha512-sf4i37nQ2LBx4m3wB74y+ubopq6W/dIzXg0FDGjsYnZHVa1Da8FH853wlL2gtUhg+xJXjfk3kUZS3BRoQeoQBQ==";
    };
    "@polka/url" = fetchurl {
      url = "https://registry.npmjs.org/@polka/url/-/url-1.0.0-next.29.tgz";
      hash = "sha512-wwQAWhWSuHaag8c4q/KN/vCoeOJYshAIvMQwD4GpSb3OiZklFfvAgmj0VCBBImRpuF/aFgIRzllXlVX93Jevww==";
    };
  };

  installDeps = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: src: ''
      mkdir -p node_modules/${name}
      tar xzf ${src} -C node_modules/${name} --strip-components=1
    '') deps
  );
in
stdenvNoCC.mkDerivation {
  pname = "openhands-agent-canvas";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@openhands/agent-canvas/-/agent-canvas-${version}.tgz";
    hash = "sha512-n76KZ9rYvYtGqZfO22tGQgXiJfufGvL8ELZB0TqczwHSAVzQ7EVJXL8XMFfRO3IpuFPuh3ECsqVMmGshuQzjgg==";
  };

  nativeBuildInputs = [ makeWrapper ];
  strictDeps = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    ${installDeps}

    mkdir -p $out/lib/agent-canvas
    cp -r . $out/lib/agent-canvas

    # uv resolves an interpreter itself; python-build-standalone downloads are
    # not runnable here, so point it at the Nix one. Wheels with compiled
    # extensions expect libstdc++ from the loader path.
    makeWrapper ${lib.getExe nodejs} $out/bin/agent-canvas \
      --add-flags $out/lib/agent-canvas/bin/agent-canvas.mjs \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs
          uv
        ]
      } \
      --set UV_PYTHON_DOWNLOADS never \
      --set UV_PYTHON ${lib.getExe python3} \
      --suffix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          stdenv.cc.cc.lib
          zlib
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Agent Canvas UI for OpenHands, running agents behind a web interface";
    homepage = "https://github.com/OpenHands/OpenHands";
    downloadPage = "https://www.npmjs.com/package/@openhands/agent-canvas";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "agent-canvas";
    platforms = lib.platforms.linux;
  };
}
