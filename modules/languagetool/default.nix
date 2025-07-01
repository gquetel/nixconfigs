{
  lib,
  config,
  pkgs,
  ...
}:

{
  services.languagetool = {
    enable = true; # Enable http-api server.
    port = 8787; # On this custom port.

    allowOrigin = ""; # Required for extensions such as thunderbird's one.
    settings = {
      # Per https://dev.languagetool.org/http-server
      # fasttextBinary & fasttextModel are "optional but strongly recommended on Linux"

      fasttextBinary = "${pkgs.fasttext}/bin/fasttext";
      fasttextModel = pkgs.fetchurl {
        name = "lid.176.bin";
        url = "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin";
        hash = "sha256-fmnsVFG8JhzHhE5J5HkqhdfwnAZ4nsgA/EpErsNidk4=";
      };
      languageModel = pkgs.linkFarm "languageModel" (
        builtins.mapAttrs (_: v: pkgs.fetchzip v) {
          en = {
            url = "https://languagetool.org/download/ngram-data/ngrams-en-20150817.zip";
            hash = "sha256-v3Ym6CBJftQCY5FuY6s5ziFvHKAyYD3fTHr99i6N8sE=";
          };
          fr = {
            url = "https://languagetool.org/download/ngram-data/ngrams-fr-20150913.zip";
            hash = "sha256-mA2dFEscDNr4tJQzQnpssNAmiSpd9vaDX8e+21OJUgQ=";
          };
        }
      );
    };

  };

}
