{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }:

let
  testdata = import ./testdata.nix { inherit pkgs; };
  runner = import ./runner.nix { inherit pkgs; };
in
{
  plain = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered + "/test-tree"; };
  nested = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive + "/test-tree"; };

  plain-with-testdata-dir = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered; };
  nested-with-testdata-dir = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive; };
  
  plain-with-testdata-subdir = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered; subpath = "test-tree"; };
  nested-with-testdata-subdir = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive; subpath = "test-tree"; };
  
  subdir-1 = runner.makeTest { name = "subdir-1"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "1-simpl"; };
  subdir-1x = runner.makeTest { name = "subdir-1x"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "1-xxxxx"; };
  subdir-2 = runner.makeTest { name = "subdir-2"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "2-negation"; };
  subdir-3 = runner.makeTest { name = "subdir-3"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "3-wildcards"; };
  subdir-4 = runner.makeTest { name = "subdir-4"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "4-escapes"; };
  subdir-9 = runner.makeTest { name = "subdir-9"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "9-expected"; };
  subdir-10 = runner.makeTest { name = "subdir-10"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "10-subdir-ignoring-itself"; };

  # Make sure the files aren't added to the store before filtering.
  shortcircuit = runner.makeTest {
    name = "nested";
    rootDir = testdata.sourceUnfilteredRecursive + "/test-tree";
    preCheck = ''
      # Instead of a file, create a fifo so that the filter would error out if it tries to add it to the store.
      rm 1-simpl/1
      mkfifo 1-simpl/1
    '';
  };

  unit-tests =
    let gitignoreNix = import ../default.nix { inherit (pkgs) lib; };
        inherit (gitignoreNix) gitignoreFilterWith gitignoreSourceWith;
        example = gitignoreFilterWith { basePath = ./.; extraRules = ''
          *.foo
          !*.bar
        ''; };
        shortcircuit = gitignoreSourceWith {
          path = {
            inherit (lib.cleanSource ./.) _isLibCleanSourceWith filter name;
            outPath = throw "do not use outPath";
            origSrc = ./.;
          };
        };
    in

    # Test that extraRules works:
    assert example ./x.foo "regular" == false;
    assert example ./x.bar "regular" == true;
    assert example ./x.qux "regular" == true;

    # Make sure outPath is not used. (It's not about the store path)
    assert lib.hasPrefix builtins.storeDir "${shortcircuit}";

    # End of test. (a drv to show a buildable attr when successful)
    pkgs.emptyFile or null;
}
