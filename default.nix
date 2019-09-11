{ lib ? import <nixpkgs/lib> }:
let
  find-files = import ./find-files.nix { inherit lib; };

  newCleanSourceWith =
    let newSrc = lib.cleanSourceWith { filter = f: t: true; src = ./.; };
    in (builtins.functionArgs lib.cleanSourceWith) ? name || newSrc ? name;

in
{
  inherit (find-files) gitignoreFilter;

  gitignoreSource =
    if newCleanSourceWith
    then
      path:
        let
          origPath = path.origPath or path;
        in
        lib.cleanSourceWith {
          name = "source";
          filter = find-files.gitignoreFilter origPath;
          src = path;
        }
    else
      path:
        if path ? _isLibCleanSourceWith
        then builtins.abort "Sorry, please update your Nixpkgs if you want to use gitignoreSource on cleanSourceWith"
        else builtins.path {
          name = "source";
          filter = find-files.gitignoreFilter path;
          inherit path;
        };
}
