{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }:

let
  testdata = import ./testdata.nix { inherit pkgs; };
  runner = import ./runner.nix { inherit pkgs; };
  gitignoreNix = (import ../. { inherit lib; });
  inherit (gitignoreNix) gitignoreSource;
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

  # https://github.com/hercules-ci/gitignore.nix/pull/71
  regression-config-with-store-path =
    pkgs.stdenv.mkDerivation {
      name = "config-with-store-path";
      src = testdata.sourceUnfiltered + "/test-tree";
      buildInputs = [ pkgs.nix ];
      NIX_PATH="nixpkgs=${pkgs.path}";
      buildPhase = ''
        # Set up an alternate nix store with a different store directory
        export TEST_ROOT=$(pwd)/test-root
        export NIX_BUILD_HOOK=
        export NIX_CONF_DIR=$TEST_ROOT/etc
        export NIX_LOCALSTATE_DIR=$TEST_ROOT/var
        export NIX_LOG_DIR=$TEST_ROOT/var/log/nix
        export NIX_STATE_DIR=$TEST_ROOT/var/nix
        export NIX_STORE_DIR=$TEST_ROOT/store
        export NIX_STORE=$TEST_ROOT/store

        mkdir -p $NIX_STORE_DIR $NIX_CONF_DIR

        # Write nix.conf - disable sandbox for nested builds
        cat > $NIX_CONF_DIR/nix.conf <<EOF
        sandbox = false
        substituters =  # none
        EOF

        nix-store --init

        # Create config directory with gitconfig that references excludesfile
        # This simulates home-manager creating a config in the store
        # Both derivations are created in one expression so excludesfile can be referenced directly
        configdir=$(nix-build --no-out-link --expr "
          let
            pkgs = import <nixpkgs> {};
            excludesfile = derivation {
              name = \"excludesfile\";
              system = builtins.currentSystem;
              builder = \"/bin/sh\";
              args = [\"-c\" \"echo -n \\\"\\\" > \\\$out\"];
            };
          in
          derivation {
            name = \"home-config\";
            system = builtins.currentSystem;
            builder = \"${pkgs.bash}/bin/bash\";
            PATH = \"${pkgs.coreutils}/bin\";
            inherit excludesfile;
            args = [\"-c\" \"
              mkdir -p \\\$out/git
              printf '[core]\\\\n    excludesfile = %s\\\\n' \\\$excludesfile > \\\$out/git/config
            \"];
          }
        ")

        # Use XDG_CONFIG_HOME pointing directly to this store path (like home-manager does)
        export XDG_CONFIG_HOME=$configdir
        echo "XDG_CONFIG_HOME is now: $XDG_CONFIG_HOME"
        echo "Config file contents:"
        cat $XDG_CONFIG_HOME/git/config

        echo "---------------"
        echo "Testing gitignoreSource with store path in git config:"
        # This calls the real main code (gitignoreSource) which will naturally
        # evaluate globalConfiguredExcludesFile when building the pattern tree
        # Without the fix: fails with "a string that refers to a store path cannot be appended to a path"
        # With the fix: succeeds (unsafeDiscardStringContext strips the context)
        if nix-instantiate --eval --expr \
            '((import ${gitignoreSource ../.} {}).gitignoreSource ./.).outPath'
        then touch $out
        else
          echo
          echo "Failed to run with a global excludes file from the nix store."
          echo "This may be because the store path gets misinterpreted as a string context."
          echo "See https://github.com/hercules-ci/gitignore.nix/pull/71"
          exit 1
        fi
      '';
      preInstall = "";
      installPhase = ":";
    };

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
    let inherit (gitignoreNix) gitignoreFilterWith gitignoreSourceWith;
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
