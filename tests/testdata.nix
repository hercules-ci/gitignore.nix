{ pkgs ? import <nixpkgs> {} }:

/*
  Programmatically specifies the test data.
 */
let
  inherit (pkgs) runCommand;

  createTree = ''
    touches() { (
        mkdir -p "$1"; cd "$1"; shift
        touch "$@"
    ); }

    create-tree() { (
        mkdir -p "$1"; cd "$1"

        touch '#' '#ignored'

        touches 1-simpl          {1,2,3,4,5,^,$,^$,$^,[,[[,],]],]]],ab,bb,\\,\\\\,simple-test}
        touches 1-simpl/1-simpl  {1,2,3,4,5,^,$,^$,$^,[,[[,],]],]]],ab,bb,\\,\\\\,simpletest}
        touches 1-xxxxx/1-simpl  {1,2}
        touch {,1-simpl/}char-class-pathalogic

        touches 2-negation       {.keep,10,20,30,40,50,60,70}

        touches 3-wildcards      {foo,bar,bbar,baz}.html
        touches 3-wildcards/html {foo,bar,bbar,baz}.html

        touches 4-escapes        {{*,o{,_,__,?,}ther}.html,other.html{,\$,\$\$}}

        touches 5-directory      {1,2,3,4,5,^,$,^$,$^,[,[[,],]],]]],ab,bb,\\,\\\\}

        mkdir 6-hash
        touch '6-hash/a' '6-hash/a#0' '6-hash/a\#1' '6-hash/a\\#2'
        touch '6-hash/b' '6-hash/b#0' '6-hash/b\#1' '6-hash/b\\#2'
        touch '6-hash/c' '6-hash/c#0' '6-hash/c\#1' '6-hash/c\\#2'
        touch '6-hash/d' '6-hash/d#0' '6-hash/d\#1' '6-hash/d\\#2'
        touch '6-hash/z' '6-hash/z#0' '6-hash/z\#1' '6-hash/z\\#2'

        mkdir 7-brackets
        touch '7-brackets/foo - Backup (0).rdl'
        touch '7-brackets/foo - backup ([0]).rdl'
        touch '7-brackets/foo - backup 0).rdl'
        touch '7-brackets/foo - backup (0.rdl'
        touch '7-brackets/foo - backup 0.rdl'
        touch '7-brackets/foo - backup 0.rdl'

        touches 9-expected       {unfiltered,filtered-via-aux-{filter,ignore,filepath}}

        touches 10-subdir-ignoring-itself/foo {foo,bar}
        echo foo >10-subdir-ignoring-itself/foo/.gitignore

        mkdir 12-empty-dir
        mkdir 12-not-empty-dir
        touch 12-not-empty-dir/just-a-regular-file
    ); }

    create-tree "$1"

    cat ${builtins.toFile "nixgitignore-ignores" ignores} > "$1/.gitignore"
    cat ${builtins.toFile "nixgitignore-ignores" ignoresAux} > "$1/aux.gitignore"
  '';

  createTreeRecursive = createTree + "\n" + ''
    cp -r "$1" "$1" 2>&1 | grep -vq 'cannot copy a directory, .*into itself' || :
  '';

  ignores = ''
    1-simpl/1
    /1-simpl/2
    /1-simpl/[35^$[]]
    /1-simpl/][\]]
    /1-simpl/[^a]b
    /1-simpl/[\\]
    simple*test

    # [^b/]har-class-pathalogic
    # this fails, but is pathalogic, so I won't cover it

    2-*/[^.]*
    !2-*/1?
    !2-*/30
    !/2-*/70
    !/40
    !50

    3-*/*foo.html
    3-*/**/bar.html

    4-*/\*.html
    4-*/o??ther.html
    4-*/o\?ther.html
    4-*/other.html$

    5-*/

    # A hash sign on a line
    #

    6-hash/a*#
    6-hash/b*\#
    6-hash/c*\\#
    6-hash/d*\\\#
    6-hash/z*

    # two bracketed classes in one rule
    7-brackets/*- [Bb]ackup ([0-9]).rdl
  '';

  ignoresAux = "/9-expected/*filepath\n";

  createSourceTree = createTree: (runCommand "test-tree" {} ''
    mkdir -p $out; cd $out;
    bash ${builtins.toFile "create-tree" createTree} test-tree
   '');

  # source is a copy of sourceUnfiltered, which lives in the nix store
  sourceUnfiltered = createSourceTree createTree;
  sourceUnfilteredRecursive = createSourceTree createTreeRecursive;

in {
  inherit sourceUnfiltered sourceUnfilteredRecursive;
}
