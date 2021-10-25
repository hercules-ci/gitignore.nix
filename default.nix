{ lib ? import <nixpkgs/lib> }:
let
  find-files = import ./find-files.nix { inherit lib; };

  newCleanSourceWith =
    let newSrc = lib.cleanSourceWith { filter = f: t: true; src = ./.; };
    in (builtins.functionArgs lib.cleanSourceWith) ? name || newSrc ? name;

  gitignoreSource =
    if newCleanSourceWith
    then
      path: gitignoreSourceWith { inherit path; }
    else
      path:
        if path ? _isLibCleanSourceWith
        then builtins.abort "Sorry, please update your Nixpkgs to 19.09 or master if you want to use gitignoreSource on cleanSourceWith"
        else lib.warn "You are using gitignore.nix with an old version of Nixpkgs that is not supported." (builtins.path {
          name = "source";
          filter = find-files.gitignoreFilter path;
          inherit path;
        });

  gitignoreSourceWith = { path }:
    lib.cleanSourceWith {
      name = "source";
      filter = find-files.gitignoreFilterWith { basePath = path.origPath or path; };
      src = path;
    };

in
{
  inherit (find-files)
    gitignoreFilter
    gitignoreFilterWith
    ;
  inherit
    gitignoreSource
    gitignoreSourceWith
    ;

}
