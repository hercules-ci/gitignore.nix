
# `gitignoreFilter`

If you want to use gitignore functionality in new ways, you may use the
`gitignoreFilter` function directly. For performance, you should keep
the number of `gitignoreFilter` calls to a minimum. It is a curried
function for good reason. After applying the first argument, the root
path of the source, it returns a function that memoizes information
about the git directory structure. The function must only be invoked
for paths at or below this root path.

### Usage example

```nix
let
  gitignore = (import (import ./nix/sources.nix)."gitignore.nix" { inherit lib; });
  inherit (gitignore) gitignoreFilterWith;

  customerFilter = src:
    let
      # IMPORTANT: use a let binding like this to memoize info about the git directories.
      srcIgnored = gitignoreFilterWith { basePath = src; extraRules = ''
        *.xml
        !i-need-this.xml
      ''; };
    in
      path: type:
         srcIgnored path type && baseNameOf path != "just-an-example-of-custom-filter-code.out";

  name = "example";
  exampleSrc = ./.;
in
  mkDerivation {
    inherit name;
    src = cleanSourceWith {
      filter = customerFilter exampleSrc;
      src = exampleSrc;
      name = name + "-source";
    };
  };
```
