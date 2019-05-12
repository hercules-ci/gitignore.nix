{ pkgs ? import <nixpkgs> {} }:

let
  inherit (pkgs) lib;
  inherit (import ../. { inherit lib; }) gitignoreFilter gitignoreSource;
  inherit (lib) concatMap flip;
  inherit (lib.attrsets) mapAttrsToList nameValuePair;
  inherit (lib.strings) concatStringsSep;
  for = l: f: concatMap f l;
  guard = b: if b then [{}] else [];

  addPath = p: subp: if subp == "" then p else p + "/${subp}";

  /*
    Make a test case.

      name:                    Name of the test case.

      rootDir:                 Source for the native git implementation.
                               This is the root of the git repo; as required
                               by the native git implementation.

      rootDir + "/${subpath}": Source for the Nix implementation, which ought to
                               discover rootDir by itself.

   */
  makeTest = {name ? "source", rootDir, subpath ? ""}:
    pkgs.runCommand "test-${name}" {
      inherit name;
      viaGit = listingViaGit { inherit name rootDir subpath; };
      viaNix = listingViaNixGitignore { inherit name rootDir subpath; };
    } ''
      if diff $viaNix $viaGit; then
        touch $out
      else
        echo
        echo "Found a difference between nix-gitignore and native git."
        echo "Above diff can be read as a 'fix' to the nix-gitignore output."
        echo "< fix by excluding this in nix-gitignore"
        echo "> fix by including this in nix-gitignore"
        exit 1;
      fi
    '';

  listingViaGit = {name ? "source", rootDir, subpath}:
    pkgs.stdenv.mkDerivation {
      name = "${name}-listing-via-git";
      src = rootDir;
      buildInputs = [pkgs.git];
      buildPhase = ''
        if ! test -d .git; then
          rm .git || true
          git init mkrepo
          mv mkrepo/.git . || true
          rm -rf mkrepo
        fi
        git add .
        git config user.email a@b.c
        git config user.name abc
        git commit -m 'Add everything'
        git archive HEAD -- ${subpath} | tar -t --quoting-style=literal | sed -e 's_/$__' -e 's@^${subpath}/*@@' | (grep -v '^$' || true) | sort >$out
      '';
      preInstall = "";
      installPhase = ":";
    };

  listingViaNixGitignore = {name ? "source", rootDir, subpath}:
    pkgs.stdenv.mkDerivation {
      name = "${name}-listing-via-nix";
      src = rootDir;
      buildInputs = [
        pkgs.git pkgs.nix pkgs.jq
        # optional 
        pkgs.git-crypt
        ];
      NIX_PATH="nixpkgs=${pkgs.path}";
      inherit subpath;
      buildPhase = ''
        export NIX_LOG_DIR=$TMPDIR
        export NIX_STATE_DIR=$TMPDIR
        test -n "$subpath" && cd $subpath
        nix-instantiate --eval --expr --json \
            --readonly-mode --option sandbox false \
            '(import ${gitignoreSource ../.}/tests/runner.nix {}).toStringNixGitignore ./.' \
          | jq -r . \
          | sort \
          >$out
      '';
      preInstall = "";
      installPhase = ":";
    };

  /* Like readDir but returning { name, type }
   */
  listDir = dir: mapAttrsToList (name: type: { inherit name type; }) (builtins.readDir dir);


  /* Like filtersource but only produces a list of paths instead of a source
   */
  traverseDirectory = predicate: dir:
    let
      recurse = subpath:
        for (listDir (dir + "/${subpath}")) ({name, type}:
          let
            subpath' = "${subpath}${if subpath == "" then "" else "/"}${name}";
          in
            for (guard (predicate (dir + "/${subpath'}") type)) ({}:
              [subpath'] ++
                for (guard (type == "directory")) (_:
                  recurse subpath'
                )
              )
        );
    in
      recurse ""
  ;

  traverseNixGitignore = dir: traverseDirectory (gitignoreFilter dir) dir;

  /* Exposed for use *inside* the nix sandbox, called by listingViaNixGitignore.
   */
  toStringNixGitignore = dir: concatStringsSep "\n" (traverseNixGitignore dir);
in
{
  inherit makeTest toStringNixGitignore listingViaNixGitignore;
}
