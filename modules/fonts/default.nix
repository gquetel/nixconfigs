{
  lib,
  config,
  pkgs,
  ...
}:

let

in
{
  config.fonts = {
    packages = with pkgs; [
      source-code-pro
      nerd-fonts.iosevka
      nerd-fonts.fira-code
      inter
      cantarell-fonts
    ];
    enableDefaultPackages = true;
  };

}
