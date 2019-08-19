{ lib ? import <nixpkgs/lib> }:
let
  find-files = import ./find-files.nix { inherit lib; };
in
{
  inherit (find-files) gitignoreFilter;
  
  gitignoreSource = path: builtins.path {
    name = "source";
    filter = find-files.gitignoreFilter path;
    inherit path;
  };
}
