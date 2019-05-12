{ lib ? import <nixpkgs/lib> }:
let
  find-files = import ./find-files.nix { inherit lib; };
in
{
  inherit (find-files) gitignoreFilter;
  gitignoreSource = p: lib.cleanSourceWith { filter = find-files.gitignoreFilter p; src = p; };
}
