let
  inputs = import ./npins;
  nixpkgs = inputs.nixpkgs;
  disko = import "${inputs.disko}/module.nix";
  colmenaModules = import "${inputs.colmena}/src/nix/hive/options.nix";
  pkgs = import inputs.nixpkgs { };
in
rec {
  colmena = {
    meta = {
      nixpkgs = import inputs.nixpkgs { };
      nodeSpecialArgs = builtins.mapAttrs (_: v: v._module.specialArgs) nixosConfigurations;
      specialArgs.lib = pkgs.lib;
    };
  } // builtins.mapAttrs (_: v: { imports = v._module.args.modules; }) nixosConfigurations;

  nixosConfigurations =
    builtins.mapAttrs
      (
        name: value:
        import "${nixpkgs}/nixos/lib/eval-config.nix" {
          lib = pkgs.lib;
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          };
          modules = [
            value
            disko
            {
              nixpkgs.overlays = [
                (final: prev: {
                  unstable = import inputs.unstable { config.allowUnfree = true; };
                })
              ];
            }
          ];
          extraModules = [ colmenaModules.deploymentOptions ];
        }
      )
      {
        scylla = import ./machines/scylla;
        strix = import ./machines/strix;
        hydra = import ./machines/hydra;
      };

}
