{
  description = "Nix functions for filtering local sources";

  outputs = { self, nixpkgs }: {
    lib = import ./default.nix {
      inherit (nixpkgs) lib;
    };

    overlay = final: prev:
      import ./default.nix {
        inherit (prev) lib;
      };

    checks.x86_64-linux = import ./tests { pkgs = nixpkgs.legacyPackages.x86_64-linux; };
  };
}
