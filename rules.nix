{ lib ? import <nixpkgs/lib> }:
/* The functions in this file translate gitignore files into filter functions.
 */
let
  inherit (builtins) compareVersions nixVersion split match;
  inherit (lib) elemAt length head filter isList reverseList foldl';
  inherit (lib.strings) substring stringLength replaceStrings concatStringsSep;

  debug = a: builtins.trace a a;
  last = l: elemAt l ((length l) - 1);

  throwIfOldNix = let required = "2.0"; in
    if compareVersions nixVersion required == -1
    then throw "nix (v${nixVersion} =< v${required}) is too old for nix-gitignore"
    else true;

in
rec {

  # type patternFunction = path -> type -> nullOr bool
  #
  # As used here

  # type filterFunction = path -> type -> bool
  #
  # As used by cleanSourceWith, builtins.path, filterSource

  # patternFunction -> filterFunction
  #
  # Make a patternFunction usable for cleanSourceWith etc.
  #
  # null values (unmatched) are converted to true (included).
  runFilterPattern =
    r: path: type:
      let
        result = r (toString path) type;
      in
        if result == null
        then true
        else result;

  # [["good/relative/source/file" true] ["bad.tmpfile" false]] -> root -> path -> nullOr bool
  filterPattern = patterns: root:
    let
      # Last item has the last say; might as well start there
      reversed = reverseList patterns;

      matchers = map (pair: let regex = match (head pair);
                            in relPath:
                                 if regex relPath == null
                                 then null
                                 else last pair
                     ) reversed;

    in
      name: _type:
        let
          relPath = lib.removePrefix ((toString root) + "/") name;
        in
          # Ideally we'd use foldr, but that crashes on big lists. At least we don't
          # have to actually match any patterns after we encounter a match.
          foldl'
            (result: matcher:
             if result == null
             then matcher relPath
             else result)
            null
            matchers
          ;

  # Combine the result of two pattern functions such that the later functions
  # may override the result of preceding ones.
  mergePattern = pa: pb: (name: type:
    let ra = pa name type;
        rb = pb name type;
    in if rb != null
       then rb
       else ra
    );

  # mergePattern unitPattern x == x
  # mergePattern x unitPattern == x
  unitPattern = name: type: null;

  # string -> [[regex bool]]
  gitignoreToRegexes = gitignore:
    assert throwIfOldNix;
    let
      # ignore -> bool
      isComment = i: (match "^(#.*|$)" i) != null;

      # ignore -> [ignore bool]
      computeNegation = l:
        let split = match "^(!?)(.*)" l;
        in [(elemAt split 1) (head split == "!")];

      # ignore -> regex
      substWildcards =
        let
          special = "^$.+{}()";
          escs = "\\*?";
          splitString =
            let recurse = str : [(substring 0 1 str)] ++
                                 (if str == "" then [] else (recurse (substring 1 (stringLength(str)) str) ));
            in str : recurse str;
          chars = s: filter (c: c != "" && !isList c) (splitString s);
          escape = s: map (c: "\\" + c) (chars s);

          # The "#" character normally starts a comment, but can be escaped with a
          # backslash to be a literal # in the pattern.
          unescapes = "#";
        in
          replaceStrings
            ((chars special)  ++ (escape unescapes) ++ (escape escs) ++ ["**/"    "**" "*"     "?"])
            ((escape special) ++ (chars unescapes)  ++ (escape escs) ++ ["(.*/)?" ".*" "[^/]*" "[^/]"]);

      # (regex -> regex) -> regex -> regex
      mapAroundCharclass = f: r: # rl = regex or list
        let slightFix = replaceStrings ["\\]"] ["]"];
        in
          concatStringsSep ""
          (map (rl: if isList rl then slightFix (elemAt rl 0) else f rl)
          (split "(\\[([^]\\\\]|\\\\.)+])" r));

      # regex -> regex
      handleSlashPrefix = l:
        let
          split = (match "^(/?)(.*)" l);
          findSlash = l: if (match ".+/.+" l) != null then "" else l;
          hasSlash = mapAroundCharclass findSlash l != l;
        in
          (if (elemAt split 0) == "/" || hasSlash
          then "^"
          else "(^|.*/)"
          ) + (elemAt split 1);

      # regex -> regex
      handleSlashSuffix = l:
        let split = (match "^(.*)/$" l);
        in if split != null then (elemAt split 0) + "($|/.*)" else l;

      # (regex -> regex) -> [regex, bool] -> [regex, bool]
      mapPat = f: l: [(f (head l)) (last l)];
    in
      map (l: # `l' for "line"
        mapPat (l: handleSlashSuffix (handleSlashPrefix (mapAroundCharclass substWildcards l)))
        (computeNegation l))
      (filter (l: !isList l && !isComment l)
      (split "\n" gitignore));

  gitignoreFilter = ign: root: filterPattern (gitignoreToRegexes ign) root;
}
