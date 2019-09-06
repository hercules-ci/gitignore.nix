{ lib ? import <nixpkgs/lib> }:
let
  find-files = import ./find-files.nix { inherit lib; };
in
{
  inherit (find-files) gitignoreFilter;
  
  gitignoreSource = path: lib.cleanSourceWith {
    name = "source";
    filter = find-files.gitignoreFilter path;
    src = path;
  };
}
