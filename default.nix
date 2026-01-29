let
  inputs = import ./npins;
  nixpkgs = inputs.nixpkgs;

  disko-module = import "${inputs.disko}/module.nix";
  colmena-modules = import "${inputs.colmena}/src/nix/hive/options.nix";
  home-manager-module = import "${inputs.home-manager}/nixos/default.nix";
  # See: https://github.com/oddlama/nix-topology
  # We don't use flakes, we import the nix-topology overlay and module as follows:
  nix-topology-overlay = import "${inputs.nix-topology}/pkgs/default.nix";
  nix-topology-module = import "${inputs.nix-topology}/nixos/module.nix";

  pkgs = import inputs.nixpkgs {
    # pkgs in topology requires rendering tools. We provide them through this
    # overlay.
    overlays = [ nix-topology-overlay ];
  };
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
            disko-module
            nix-topology-module
            home-manager-module
            {
              nixpkgs.overlays = [
                (final: prev: {
                  unstable = import inputs.unstable { config.allowUnfree = true; };
                })
              ];
            }
          ];
          # Colmena-specific options, not required for machine config
          # but required to define deployment options.
          extraModules = [ colmena-modules.deploymentOptions ];
        }
      )
      {
        scylla = import ./machines/scylla;
        strix = import ./machines/strix;
        hydra = import ./machines/hydra;
        garmr = import ./machines/garmr;
        vapula = import ./machines/vapula;
        charybdis = import ./machines/charybdis;
      };

  # nix-topology expects a pkgs argument that already have a nix-topology overlay.
  topology = import inputs.nix-topology {
    pkgs = pkgs;
    modules = [
      {
        nixosConfigurations = nixosConfigurations;
      }
      ./topology.nix
    ];
  };
}
