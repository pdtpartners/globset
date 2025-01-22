{ lib }:
let
  pattern = import ./src/pattern.nix { inherit lib; };
  path = import ./src/path.nix { inherit lib; };
  glob = import ./src/glob.nix { inherit lib; };
  match = import ./src/match.nix { inherit lib; };

in {
  inherit (pattern)
    handleNoMeta firstUnescapedMeta unescapeMeta unescapeAlternates isZeroLengthPattern
    parseCharClass inCharRange matchesCharClass;

  inherit (path) lastIndexSlash findNextSeparator;

  inherit (glob) globs glob globSegments globSegment globDoublestar;

  inherit (match) match;
}
