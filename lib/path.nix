{ lib }:
let
  inherit (lib) filter head mapAttrs tail;

  # absolutePathComponentsBetween : PathOrString -> PathOrString -> [String]
  # absolutePathComponentsBetween ancestor descendant
  #
  # Returns the path components that form the path from ancestor to descendant.
  # Will not return ".." components, which is a feature. Throws when ancestor
  # and descendant arguments aren't in said relation to each other.
  #
  # Example:
  #
  #   absolutePathComponentsBetween /a     /a/b/c == ["b" "c"]
  #   absolutePathComponentsBetween /a/b/c /a/b/c == []
  absolutePathComponentsBetween =
    # TODO: port the tests from https://github.com/NixOS/nixpkgs/pull/112083
    ancestor: descendant:
      let
        a' = /. + ancestor;
        go = d:
          if a' == d
          then []
          else if d == /.
          then throw "absolutePathComponentsBetween: path ${toString ancestor} is not an ancestor of ${toString descendant}"
          else go (dirOf d) ++ [(baseNameOf d)];
      in
        go (/. + descendant);

  /*
      Memoize a function that takes a path argument.
      Example:
        analyzeTree = dir:
          let g = memoizePathFunction (p: t: expensiveFunction p t) (p: {}) dir;
          in presentExpensiveData g;
      Type:
        memoizePathFunction :: (Path -> Type -> a) -> (Path -> a) -> Path -> (Path -> a)
    */
  memoize =
    # Function to memoize
    f:
    # What to return when a path does not exist, as a function of the path
    missing:
    # Filesystem location below which the returned function is defined. `/.` may be acceptable, but a path closer to the data of interest is better.
    root:

    # TODO: port the tests from https://github.com/NixOS/nixpkgs/pull/112083

    let
      makeTree = dir: type: {
        value = f dir type;
        inherit type;
        children =
          if type == "directory"
            then mapAttrs
                  (key: type: makeTree (dir + "/${key}") type)
                  (builtins.readDir dir)
            else {};
      };

      # This is where the memoization happens
      tree = makeTree root (
        # We can't query the type of a store path in Nix without readFileType in
        # pure mode, so we assume.
        "directory"
      );

      lookup = notFound: list: subtree:
        if list == []
        then subtree.value
        else if subtree.children ? ${head list}
        then lookup notFound (tail list) subtree.children.${head list}
        else notFound;
    in
      path: lookup
        (missing path)
        (absolutePathComponentsBetween root path)
        tree;
in
{
  inherit memoize absolutePathComponentsBetween;
}
