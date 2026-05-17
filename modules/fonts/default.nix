{
  lib,
  config,
  pkgs,
  ...
}:

let
  marianne = pkgs.stdenv.mkDerivation {
    name = "marianne-font";
    src = pkgs.fetchzip {
      url = "https://gitlab-forge.din.developpement-durable.gouv.fr/dreal-pdl/csd/propre.brochure/-/archive/master/propre.brochure-master.tar.gz?path=fonts/marianne/truetype";
      hash = "sha256-XEyDeJ4iCjDyWBHLCFdsqb5Riel0qE9ZJWFg6BuOxBA=";
      extension = "tar.gz";
      stripRoot = false;
    };
    installPhase = ''
      mkdir -p $out/share/fonts/truetype
      cp propre.brochure-master-fonts-marianne-truetype/fonts/marianne/truetype/*.ttf $out/share/fonts/truetype/
    '';
  };
in
{
  config.fonts = {
    packages = with pkgs; [
      marianne
      source-code-pro
      nerd-fonts.iosevka
      nerd-fonts.fira-code
      inter
      cantarell-fonts
    ];
    enableDefaultPackages = true;
    fontconfig.defaultFonts = {
      monospace = [ "Source Code Pro" ];
      sansSerif = [ "Inter" ];
    };
  };

}
