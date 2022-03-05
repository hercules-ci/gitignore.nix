
# Make Nix precisely emulate gitignore

This goal of this project lets you include local sources in your [Nix](https://builtwithnix.org) projects,
while taking [gitignore files](https://git-scm.com/docs/gitignore) into account.

Note that although this project does a good job at emulating git's behavior, it is not the same implementation!

# Installation

## Recommended with Niv
```
nix-env -iA niv -f https://github.com/nmattia/niv/tarball/master
niv init
niv add hercules-ci/gitignore.nix
```

## With Flakes

Although Flakes usually process sources within the flake using the git fetcher, which takes care of ignoring in its own peculiar way, you can use gitignore.nix to filter sources outside of a flake. You can load flake-based expressions via `builtins.getFlake (toString ./.)` for example or via [`flake-compat`](https://github.com/edolstra/flake-compat).

```nix
# // flake.nix
{
  inputs.gitignore = {
    url = "github:hercules-ci/gitignore.nix";
    # Use the same nixpkgs
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, /* other, inputs, */ gitignore }:
  let
    inherit (gitignore.lib) gitignoreSource;
  in {
    packages.x86_64.hello = mkDerivation {
      name = "hello";
      src = gitignoreSource ./vendored/hello;
    };
  };
}
```

## Plain Nix way

```nix
let
  gitignoreSrc = pkgs.fetchFromGitHub { 
    owner = "hercules-ci";
    repo = "gitignore.nix";
    # put the latest commit sha of gitignore Nix library here:
    rev = "";
    # use what nix suggests in the mismatch message here:
    sha256 = "sha256:0000000000000000000000000000000000000000000000000000";
  };
  inherit (import gitignoreSrc { inherit (pkgs) lib; }) gitignoreSource;
in
  <your nix expression>
```

Or using only `nixpkgs/lib` and only evaluation-time fetching:

```nix
import (builtins.fetchTarball "https://github.com/hercules-ci/gitignore.nix/archive/000000000000000000000000000000000000000000000000000".tar.gz") {
  lib = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/000000000000000000000000000000000000000000000000000".tar.gz" + "/lib");
}
```

# Usage

```nix
mkDerivation {
  name = "hello";
  src = gitignoreSource ./vendored/hello;
}
```

```
gitignoreSource :: path -> path
```

Returns result of cleanSourceWith, usable as a path but also composable.

```
gitignoreFilter :: path -> (path -> type -> bool)

f = gitignoreFilter path
```

Parentheses in the type emphasize that a partial application memoizes the git metadata. You can use Nixpkgs' [`cleanSourceWith`](https://github.com/NixOS/nixpkgs/blob/d1bb36d5cb5b78111f799eb26f5f17e5979bc746/lib/sources.nix#L35-L67) to compose with other filters (by logical _and_) or to set a `name`.

`path`: a path being the root or a subdirectory of a local git repository

`f`: a function that returns `false` for files that should be ignored according to gitignore rules, but only for paths at or below `path`.

See [gitignoreFilter](docs/gitignoreFilter.md) for an example.

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

| Feature \ Implementation | cleanSource | fetchGit/fetchTree | [siers](https://github.com/siers/nix-gitignore) | [siers recursive](https://github.com/siers/nix-gitignore) | [icetan](https://github.com/icetan/nix-git-ignore-source) | [Profpatsch](https://github.com/Profpatsch/nixperiments/blob/master/filterSourceGitignore.nix) | [numtide](https://github.com/numtide/nix-gitignore) | this project
|-|-|-|-|-|-|-|-|-|
|Reproducible                                     | ✔️ | ! | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️
|Includes added but ignored files                 |   | ✔️ |   |   |   |   | ✔️ |
|Uses user tooling rules from dotfiles            |   |   | ? |   |   |   |   | ✔️
|Ignores .git                                     | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ 
|No special Nix configuration                     | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |   | ✔️ 
|No import from derivation                        | ✔️ | ! | ✔️ |   | ✔️ | ✔️ | ✔️ | ✔️ 
|Uses subdirectory gitignores                     |   | ✔️ |   | ✔️ |   |   | ✔️ | ✔️ 
|Uses parent gitignores                           |   | ✔️ |   |   |   |   |✔️ ?| ✔️ 
|Uses user gitignores                             |   |✔️ ?|   |   |   |   | ✔️ | ✔️ 
|Has a test suite                                 |   |✔️ ?| ✔️ | ✔️ | ✔️ |   | ? | ✔️
|Works with `restrict-eval` / Hydra               | ✔️ | ? | ✔️ |   | ✔️ | ✔️ |   | ✔️
|Descends into submodule correctly                |   | ✔️ | ? | ? | ? | ? |✔️ ?| ? #8 
|Included in nixpkgs                              | ✔️ | ✔️ | ✔️ | ✔️ |   |   |   |
|No traversal of ignored dirs<br/>(perf on large repos) | - |   | ✔️ |✔️ ?| ✔️ |✔️ ?|✔️ ?| ✔️ ? 

|   | Legend |
|---|-------------------------------------|
|✔️  | Supported
|✔️ ?| Probably supported
|   | Not supported
|?  | Probably not supported
|-  | Not applicable or depends
|!  | Caveats

Caveats:

 - `fetchGit` is not reproducible. It has at least [one](https://github.com/NixOS/nix/pull/4635) serious reproducibility problem that requires a breaking change to fix. Unlike fixed-output derivations, a built-in fetcher does not have a pinned implementation!
 - `fetchGit` blocks the evaluator, just like import from derivation

Please open a PR if you've found another feature, determined any of the '?' or found an inaccuracy!

# Security

Files not matched by gitignore rules will end up in the Nix store, which is readable by any process.

gitignore.nix does not yet understand `git-crypt`'s metadata, so don't call `gitignoreSource` on directories containing such secrets or their parent directories.
This applies to any Nix function that uses the `builtins.path` or `builtins.filterSource` functions.

# Contributing

This project isn't perfect (yet) so please submit test cases and fixes as pull requests. Before doing anything drastic, it's a good idea to open an issue first to discuss and optimize the approach.

# Thanks

A great shoutout to @siers for writing the intial test suite and rule translation code!
