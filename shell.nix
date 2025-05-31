let
  inputs = import ./npins;
  pkgs = import inputs.nixpkgs { };
  nixos-anywhere = pkgs.callPackage "${inputs.nixos-anywhere}/src/default.nix" { };
  agenix = pkgs.callPackage "${inputs.agenix}/pkgs/agenix.nix" { };
in
pkgs.mkShell {
  nativeBuildInputs = [
    nixos-anywhere    
    pkgs.colmena
    pkgs.npins
    agenix
  ];
}
