let
inputs = import ./npins;
pkgs = import inputs.nixpkgs {};
nixos-anywhere = pkgs.callPackage "${inputs.nixos-anywhere}/src/default.nix" {};
in 
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.colmena
    pkgs.npins
    nixos-anywhere
  ];

}