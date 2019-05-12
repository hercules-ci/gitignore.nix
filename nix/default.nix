{ sources ? import ./sources.nix }:
let
  config = {};
  overlays = [(super: self: {
    inherit (import sources.niv {}) niv;
  })];
  pkgs = import sources.nixpkgs { inherit overlays config; };
in
  pkgs
