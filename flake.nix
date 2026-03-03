{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      flake-utils,
      fenix,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            fenix.overlays.default
            (import ./overlay.nix)
          ];
        };
      in
      {
        formatter = pkgs.nixfmt-tree;

        packages = {
          default = self.packages.${system}.sinh-x-zeroclaw;
          inherit (pkgs)
            sinh-x-zeroclaw
            zeroclaw-web
            ;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ pkgs.sinh-x-zeroclaw ];
          packages = [
            pkgs.rust-analyzer
            pkgs.sinh-x-zeroclaw
          ];
        };
      }
    )
    // {
      overlays.default = import ./overlay.nix;
    };
}
