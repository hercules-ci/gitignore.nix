
# `gitignore` for Nix that just works

This project lets you include local sources in your [Nix](https://builtwithnix.org) projects,
while taking [gitignore files](https://git-scm.com/docs/gitignore) into account.

# Installation

## Recommended with Niv
```
nix-env -iA niv -f https://github.com/nmattia/niv/tarball/master
niv init
niv add hercules-ci/gitignore
```

## Plain Nix way

```nix
let
  gitignoreSrc = pkgs.fetchFromGitHub { 
    owner = "hercules-ci";
    repo = "gitignore";
    # put the latest commit sha of gitignore Nix library here:
    rev = "";
    # use what nix suggests in the mismatch message here:
    sha256 = "sha256:0000000000000000000000000000000000000000000000000000";
  };
  inherit (import gitignoreSrc { inherit (pkgs) lib; }) gitignoreSource;
in
  <your nix expression>
```

# Usage

```nix
mkDerivation {
  name = "hello";
  src = gitignoreSource ./vendored/hello;
}
```

# Features

 - Subdirectories just work
 - Source hashes only change when output changes
 - Not impacted by large or inaccessible ignored directories
 - Composes with `cleanSourceWith`
 - Reads user git configuration; no need to bother your team with your tool config.
 - Also works with restrict-eval enabled (if avoiding `fetchFromGitHub`)
 - No import from derivation ("IFD")

# Contributing

This project isn't perfect (yet) so please submit test cases and fixes as pull requests. Before doing anything drastic, it's a good idea to open an issue first to discuss and optimize the approach.

# Thanks

A great shoutout to @siers for writing the intial test suite and rule translation code!
