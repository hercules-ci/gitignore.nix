{ lib ? import <nixpkgs/lib> }:
/* The functions in this file translate gitignore files into filter functions.
 */
let
  inherit (builtins) compareVersions nixVersion split match;
  inherit (lib) elemAt length head filter isList;
  inherit (lib.strings) substring stringLength replaceStrings concatStringsSep;

  debug = a: builtins.trace a a;
  last = l: elemAt l ((length l) - 1);

  throwIfOldNix = let required = "2.0"; in
    if compareVersions nixVersion required == -1
    then throw "nix (v${nixVersion} =< v${required}) is too old for nix-gitignore"
    else true;

in
rec {
  # [["good/relative/source/file" true] ["bad.tmpfile" false]] -> root -> path
  filterPattern = patterns: root:
    (name: _type:
      let
        relPath = lib.removePrefix ((toString root) + "/") name;
        matches = pair: (match (head pair) relPath) != null;
        matched = map (pair: [(matches pair) (last pair)]) patterns;
      in
        last (last ([[true true]] ++ (filter head matched)))
    );

  # TODO: we only care about the last match, so it seems we can do a reverse
  #       scan per file and represent the outcome as true, false, and null for
  #       nothing said => default to true after all rules are processed.
  runFilterPattern' = r: path: type: last (last ([[true true]] ++ r (toString path) type));
  filterPattern' = patterns: root:
    (name: _type:
      let
        relPath = lib.removePrefix ((toString root) + "/") name;
        matches = pair: (match (head pair) relPath) != null;
        matched = map (pair: [(matches pair) (last pair)]) patterns;
      in
        filter head matched
    );
  mergePattern' = pa: pb: (name: type: pa name type ++ pb name type);
  unitPattern' = name: type: [];

  # string -> [[regex bool]]
  gitignoreToPatterns = gitignore:
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
        in
          replaceStrings
            ((chars special)  ++ (escape escs) ++ ["**/"    "**" "*"     "?"])
            ((escape special) ++ (escape escs) ++ ["(.*/)?" ".*" "[^/]*" "[^/]"]);

      # (regex -> regex) -> regex -> regex
      mapAroundCharclass = f: r: # rl = regex or list
        let slightFix = replaceStrings ["\\]"] ["]"];
        in
          concatStringsSep ""
          (map (rl: if isList rl then slightFix (elemAt rl 0) else f rl)
          (split "(\\[([^\\\\]|\\\\.)+])" r));

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

  gitignoreFilter = ign: root: filterPattern (gitignoreToPatterns ign) root;
  gitignoreFilter' = ign: root: filterPattern' (gitignoreToPatterns ign) root;
}
