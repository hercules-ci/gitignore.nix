let
  sources = import ./sources.nix;
  inherit (import ./dimension.nix { lib = import (sources.nixpkgs + "/lib"); })
    dimension
  ;
  in
  dimension "Nixpkgs" {
    "nixpkgs-19_03" = sources."nixos-19.03";
    "nixpkgs-19_09" = sources."nixos-19.09";
    "nixpkgs-21_05" = sources."nixos-21.05";
  } (_key: nixpkgs:
    import ../tests/default.nix { pkgs = import ./default.nix { inherit nixpkgs; }; }
  )

