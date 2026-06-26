{
  description = "Modular rofi theme suite with NixOS and Stylix support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    # Per-system outputs (packages)
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          default = pkgs.callPackage ./nix/default.nix { src = self; };
        };
      }
    )) // {
      # System-agnostic outputs (Home Manager modules)
      homeManagerModules = {
        default = import ./nix/stylix.nix;
      };
    };
}
