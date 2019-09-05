# Basic git INI-like file format parser
#
# Probably not feature complete anytime soon...
#
# Notable omissions:
#  - multiline values (if supported??)
#  - proper subsections
#  - includes
#  - conditional includes
#  - keys with embedded whitespace
#
# Low hanging fruit:
#  - group by section if you need to query the file often
#
# Unknowns:
#  - whitespace before section header?
#  - what if no section is specified before first item?
#
{ lib ? import <nixpkgs/lib>, ... }:
let
  inherit (lib.strings) splitString hasPrefix removePrefix removeSuffix replaceStrings;
  inherit (lib.lists) foldl' head tail;

  parseIniText = text:
    let
      rawLines = splitString "\n" text;
      folded = foldl' step zero rawLines;
      zero = { section = "";
               items = [];
             };
      step = r@{ section, items }: line:
        if hasPrefix "[" line
        then r // {
          section = removePrefix "[" (removeSuffix "]" line);
        }
        else if builtins.match ".*=.*" line != null then
        let
          s = splitString "=" line;
          s0 = head s;
          key = replaceStrings [" " "\t"] ["" ""] s0;
          v = removePrefix "${s0}=" line;
          value = lstrip v;
        in
          r // {
            items = items ++ [{ inherit section key value; }];
          }
        else
          r
      ;
    in 
      folded.items
  ;
  lstrip = s: if hasPrefix " " s then lstrip (removePrefix " " s)
              else if hasPrefix "\t" s then lstrip (removePrefix "\t" s)
              else s;
  parseIniFile = p:
    builtins.addErrorContext ("while parsing INI file " + toString p) (
      parseIniText (builtins.readFile p)
    )
  ;
in {
  inherit parseIniText parseIniFile;
}
