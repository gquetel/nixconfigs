{
  lib,
  config,
  pkgs,
  ...
}:
{
  programs.firefox = {
    enable = true;
    policies = {
      # Add custom @np aliases for nix packages search and @no for nix options.
      SearchEngines = {
        Add = [
          {
            Alias = "@np";
            Description = "Search in NixOS Packages";
            IconURL = "https://nixos.org/favicon.png";
            Method = "GET";
            Name = "NixOS Packages";
            URLTemplate = "https://search.nixos.org/packages?from=0&size=200&sort=relevance&type=packages&query={searchTerms}";
          }
          {
            Alias = "@no";
            Description = "Search in NixOS Options";
            IconURL = "https://nixos.org/favicon.png";
            Method = "GET";
            Name = "NixOS Options";
            URLTemplate = "https://search.nixos.org/options?from=0&size=200&sort=relevance&type=packages&query={searchTerms}";
          }
          {
            Alias = "@nw";
            Description = "Search in NixOS Wiki";
            IconURL = "https://nixos.org/favicon.png";
            Method = "GET";
            Name = "NixOS Wiki";
            URLTemplate = "https://wiki.nixos.org/w/index.php?search={searchTerms}";
          }
        ];
      };
    };
  };
}
