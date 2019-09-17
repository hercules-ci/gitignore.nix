{ sources ? import ./sources.nix, nixpkgs ? sources.nixpkgs }:
let
  config = {};
  overlays = [(super: self: {
    inherit (import sources.niv {}) niv;
  })];
  pkgs = import nixpkgs { inherit overlays config; };
in
  pkgs
