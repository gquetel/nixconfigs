{
  lib,
  stdenv,
  python3,
  makeWrapper,
  fetchFromGitHub,
  chromium,
  xorg,
  undetected-chromedriver,
  ...
}:
let
  selenium' = python3.pkgs.callPackage ../selenium { };
  python3-undetected-chromedriver' = python3.pkgs.undetected-chromedriver.override {
    selenium = selenium';
  };
  undetected-chromedriver' = undetected-chromedriver.overrideAttrs (_old: {
    nativeBuildInputs = [ (python3.withPackages (_ps: [ python3-undetected-chromedriver' ])) ];
  });
  python = python3.withPackages (
    p: with p; [
      bottle
      waitress
      selenium'
      func-timeout
      psutil
      prometheus-client
      requests
      certifi
      packaging
      websockets
      deprecated
      mss
      xvfbwrapper
    ]
  );

  path = lib.makeBinPath [
    chromium
    undetected-chromedriver'
    xorg.xorgserver
  ];
in
stdenv.mkDerivation {
  # TODO: Add this to npins.

  pname = "flaresolverr-21hsmw";
  version = "23273a62a0d1f5cf3afb89a3ca016053ad82f88b";
  src = fetchFromGitHub {
    owner = "21hsmw";
    repo = "FlareSolverr";
    rev = "23273a62a0d1f5cf3afb89a3ca016053ad82f88b";
    hash = "sha256-yb43jzBIxHAhsReZUuGWNduyM2Qm/P+FaSTQf1O06ew=";
  };
  date = "2025-01-19";
  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    substituteInPlace src/utils.py \
      --replace 'PATCHED_DRIVER_PATH = None' 'PATCHED_DRIVER_PATH = "${undetected-chromedriver'}/bin/undetected-chromedriver"'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/opt
    cp -r * $out/opt/

    makeWrapper ${python}/bin/python $out/bin/flaresolverr \
      --add-flags "$out/opt/src/flaresolverr.py" \
      --set PATH "${path}"

    runHook postInstall
  '';

  meta = with lib; {
    mainProgram = "flaresolverr";
    maintainers = with lib.maintainers; [ xddxdd ];
    description = "Proxy server to bypass Cloudflare protection, with 21hsmw modifications to support nodriver";
    homepage = "https://github.com/21hsmw/FlareSolverr";
    license = licenses.mit;
    # broken = true;
    # Platform depends on chromedriver
    inherit (undetected-chromedriver'.meta) platforms;
  };
}
