{ lib }:
let
  inherit (builtins) head replaceStrings stringLength substring tail pathExists;

  inherit (lib) stringToCharacters;

  inherit (lib.filesystem) pathType;

in rec {
  /* Function: handleNoMeta
     	Type: Path -> String -> Bool -> [String]
     	Handles pattern matching when no meta characters are present.
  */
  handleNoMeta = root: pattern': firstSegment:
    let
      escapedPattern = unescapeMeta pattern';
      escapedPath = root + "/${escapedPattern}";
      isDirectory = (pathType escapedPath) == "directory";
    in if pathExists escapedPath && (!firstSegment || !isDirectory) then
      [ escapedPattern ]
    else
      [ ];

  /* Function: firstUnescapedMeta
      Type: String -> Int
      Returns index of first unescaped meta character or -1 if none found.
  */
  firstUnescapedMeta = str:
    let
      chars = stringToCharacters str;

      find = i: chars:
        if chars == [ ] then
          -1
        else
          let
            char = head chars;
            rest = tail chars;
          in if char == "*" then
            i
          else if char == "\\" then
            if rest == [ ] then -1 else find (i + 2) (tail rest)
          else
            find (i + 1) rest;

    in find 0 chars;

  /* Function: unescapeMeta
      Type: String -> String
      Unescapes meta characters in a pattern string.
  */
  unescapeMeta = pattern: replaceStrings [ "\\*" ] [ "*" ] pattern;

  /* Function: isZeroLengthPattern
      Type: String -> Bool
      Determines if a pattern effectively matches zero-length strings.
  */
  isZeroLengthPattern = pattern:
    pattern == "" || pattern == "*" || pattern == "**" || pattern == "/**"
    || pattern == "**/" || pattern == "/**/";
}
