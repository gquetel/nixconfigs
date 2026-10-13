{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:

# Builds only snd-hda-scodec-cs35l41 from the kernel source, with a patched
# quirk table. The module goes in updates/, so depmod selects it over the
# in-tree module. The patch fails to apply when the kernel contains the fix:
# then remove this package.
let
  modDir = "sound/hda/codecs/side-codecs";
in
stdenv.mkDerivation {
  pname = "cs35l41-hda-quirk";
  inherit (kernel) version src;

  patches = [ ./cs35l41-dragonfly-g3-boost.patch ];

  # Extract only the sound/hda tree.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xf $src -C source --strip-components=1 --wildcards '*/sound/hda'
    cd source
    runHook postUnpack
  '';

  # Replace the in-tree Makefile so that only this module is built.
  postPatch = ''
    cat > ${modDir}/Makefile <<'EOF'
    ccflags-y += -I$(src)/../../common
    snd-hda-scodec-cs35l41-y := cs35l41_hda.o cs35l41_hda_property.o
    obj-m += snd-hda-scodec-cs35l41.o
    EOF
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild
    make ${lib.escapeShellArgs kernelModuleMakeFlags} -j$NIX_BUILD_CORES \
      -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/${modDir} modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 ${modDir}/snd-hda-scodec-cs35l41.ko \
      $out/lib/modules/${kernel.modDirVersion}/updates/snd-hda-scodec-cs35l41.ko
    runHook postInstall
  '';

  meta = {
    description = "CS35L41 HDA driver with external boost for HP Elite Dragonfly G3";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
