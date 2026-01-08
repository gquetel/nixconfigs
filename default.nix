let
  inputs = import ./npins;
  nixpkgs = inputs.nixpkgs;
  disko = import "${inputs.disko}/module.nix";
  colmenaModules = import "${inputs.colmena}/src/nix/hive/options.nix";

  # See: https://github.com/oddlama/nix-topology
  # We don't use flakes, we import the nix-topology overlay and module as follows:
  nix-topology-overlay = import "${inputs.nix-topology}/pkgs/default.nix";
  nix-topology-module = import "${inputs.nix-topology}/nixos/module.nix";

  pkgs = import inputs.nixpkgs { };
in
rec {
  colmena = {
    meta = {
      nixpkgs = import inputs.nixpkgs { };
      nodeSpecialArgs = builtins.mapAttrs (_: v: v._module.specialArgs) nixosConfigurations;
      specialArgs.lib = pkgs.lib;
    };
  }
  // builtins.mapAttrs (_: v: { imports = v._module.args.modules; }) nixosConfigurations;

  # Output of this derivation: NixOS System Configurations.
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
            nix-topology-module
            {
              nixpkgs.overlays = [
                (final: prev: {
                  unstable = import inputs.unstable { config.allowUnfree = true; };
                })
                nix-topology-overlay
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
        garmr = import ./machines/garmr;
        vapula = import ./machines/vapula;
      };

  # I am unsure, this is required way to do declare topology.
  topologyPkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ nix-topology-overlay ];
  };

  topology = import inputs.nix-topology {
    pkgs = topologyPkgs;
    modules = [
      {
        nixosConfigurations = nixosConfigurations;
      }
      ./topology.nix

    ];
  };
}
