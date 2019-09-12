
# Make Nix precisely emulate gitignore

This goal of this project lets you include local sources in your [Nix](https://builtwithnix.org) projects,
while taking [gitignore files](https://git-scm.com/docs/gitignore) into account.

Note that although this project does a good job at emulating git's behavior, it is not the same implementation!

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

 - Reads parent gitignores even if only pointed at a subdirectory
 - Source hashes only change when output changes
 - Not impacted by large or inaccessible ignored directories
 - Composes with `cleanSourceWith`
 - Reads user git configuration; no need to bother your team with your tool config.
 - Also works with restrict-eval enabled (if avoiding `fetchFromGitHub`)
 - No import from derivation ("IFD")
 - Name and hash are not sensitive to checkout location

## Comparison

| Feature \ Implementation | cleanSource | [siers](https://github.com/siers/nix-gitignore) | [siers recursive](https://github.com/siers/nix-gitignore) | [icetan](https://github.com/icetan/nix-git-ignore-source) | [Profpatsch](https://github.com/Profpatsch/nixperiments/blob/master/filterSourceGitignore.nix) | [numtide](https://github.com/numtide/nix-gitignore) | this project
|-|-|-|-|-|-|-|-|
|Ignores .git                             | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ 
|No special Nix configuration             | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |   | ✔️ 
|No import from derivation                | ✔️ | ✔️ |   | ✔️ | ✔️ | ✔️ | ✔️ 
|Uses subdirectory gitignores             |   |   | ✔️ |   |   | ✔️ | ✔️ 
|Uses parent gitignores                   |   |   |   |   |   |✔️ ?| ✔️ 
|Uses user gitignores                     |   |   |   |   |   | ✔️ | ✔️ 
|Has a test suite                         |   | ✔️ | ✔️ | ✔️ |   | ? | ✔️
|Works with `restrict-eval` / Hydra       | ✔️ | ✔️ |   | ✔️ | ✔️ |   | ✔️
|Descends into submodule correctly        |   | ? | ? | ? | ? |✔️ ?| ? #8 
|Included in nixpkgs                      | ✔️ | ✔️ | ✔️ |   |   |   |
<!-- |No traversal of ignored dirs             | - | ✔️ |✔️ ?| ✔️ |✔️ ?|✔️ ?| ✔️ ? -->

|   | Legend |
|---|-------------------------------------|
|✔️  | Supported
|✔️ ?| Probably supported
|   | Not supported
|?  | Probably not supported
|-  | Not applicable or depends


Please open a PR if you've found another feature, determined any of the '?' or found an inaccuracy!

# Contributing

This project isn't perfect (yet) so please submit test cases and fixes as pull requests. Before doing anything drastic, it's a good idea to open an issue first to discuss and optimize the approach.

# Thanks

A great shoutout to @siers for writing the intial test suite and rule translation code!
