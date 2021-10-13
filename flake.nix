{
  description = "Nix functions for filtering local git sources";

  outputs = { self, nixpkgs }: {
    lib = import ./default.nix {
      inherit (nixpkgs) lib;
    };

    overlay = final: prev: import ./default.nix {
      inherit (prev) lib;
    };
  };
}
