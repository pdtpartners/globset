{ lib }:
let
  inherit (builtins) stringLength substring;

  path = import ./path.nix { inherit lib; };
  inherit (import ./pattern.nix { inherit lib; }) isZeroLengthPattern;

  /* Helper: charAt
     Type: String -> Int -> String
     Gets character at given index.
  */
  charAt = str: i: substring i 1 str;

  /* Helper: isSeparator
     Type: String -> Bool
     Checks if character is a path separator.
  */
  isSeparator = char: char == "/";

in {
  /* Function: match
     Type: String -> String -> Bool

     Determines whether a given file name matches a glob pattern.

     This function supports single `*` wildcards matching any sequence of characters
     except directory separators, double `**` wildcards matching any sequence of
     characters including directory separators, and escaping of meta characters
     using backslashes. This is useful for testing patterns against file names or paths.
  */
  # Examples:
  #   match "a*/b" "abc/b"  # Returns true
  #   match "a*/b" "a/c/b"  # Returns false
  #   match "**/c" "a/b/c"  # Returns true
  #   match "**/c" "a/b"    # Returns false
  #   match "a\\*b" "ab"    # Returns false
  #   match "a\\*b" "a*b"   # Returns true

  match = pattern: name:
    let
      patLen = stringLength pattern;

      nameLen = stringLength name;

      doMatch = { nameIdx, patIdx, startOfSegment, starBacktrack
        , doublestarBacktrack }@args:
        if nameIdx >= nameLen then
          isZeroLengthPattern (substring patIdx (patLen - patIdx) pattern)
        else if patIdx >= patLen then
          handleBacktrack args
        else
          let
            nameChar = charAt name nameIdx;

            patChar = charAt pattern patIdx;

            isStar = patChar == "*";

            isEscape = patChar == "\\";

          in if isStar then
            handleStar args
          else if isEscape && ((patIdx + 1) >= patLen) then
          # todo: ErrBadPattern
            false
          else if patChar == nameChar then
            doMatch (args // {
              nameIdx = nameIdx + 1;
              # If escaped, skip an additional rune.
              patIdx = patIdx + 1 + (if isEscape then 1 else 0);
              startOfSegment = isSeparator patChar;
            })
          else
            handleBacktrack args;

      handleStar = args:
        let
          # Check ahead for a second '*'.
          nextPatIdx = args.patIdx + 1;

          isDoublestar = nextPatIdx < patLen && charAt pattern nextPatIdx
            == "*";

          starBacktrack = {
            inherit (args) nameIdx;
            # Doublestar must begin with separator, otherwise we're going to
            # treat it like a single star like bash.
            patIdx = nextPatIdx + (if isDoublestar then 1 else 0);
          };

          # Doublestar must also end with separator, treating as single star.
          doublestarAfterChar = charAt pattern (nextPatIdx + 1);

          doublestarBacktrack = {
            inherit (args) nameIdx;
            # Add two to be after the separator.
            # e.g. '**/?' where nextPatIdx is index of '?'.
            patIdx = nextPatIdx + 2;
          };

        in if isDoublestar && args.startOfSegment && nextPatIdx + 1
        >= patLen then
        # Pattern ends in `/**`, return true.
          true
        else if isDoublestar && args.startOfSegment
        && isSeparator doublestarAfterChar then
        # Handle double star logic.
          doMatch (args // {
            inherit doublestarBacktrack;
            inherit (doublestarBacktrack) patIdx;
            starBacktrack = null;
          })
        else
        # Handle single star logic.
          doMatch (args // {
            inherit starBacktrack;
            inherit (starBacktrack) patIdx;
            startOfSegment = false;
          });

      handleBacktrack = args:
        let
          starBacktrack = {
            inherit (args.starBacktrack) patIdx;
            nameIdx = args.starBacktrack.nameIdx + 1;
          };

          starNameChar = charAt name args.starBacktrack.nameIdx;

          nextSeparatorIdx =
            path.findNextSeparator name args.doublestarBacktrack.nameIdx;

          doublestarBacktrack = {
            inherit (args.doublestarBacktrack) patIdx;
            nameIdx = nextSeparatorIdx + 1;
          };

        in if args.starBacktrack != null && !isSeparator starNameChar then
          doMatch (args // {
            inherit starBacktrack;
            inherit (starBacktrack) nameIdx;
            patIdx = args.starBacktrack.patIdx;
            startOfSegment = false;
          })
        else if args.doublestarBacktrack != null && nextSeparatorIdx != -1 then
          doMatch (args // {
            inherit doublestarBacktrack;
            inherit (doublestarBacktrack) nameIdx patIdx;
            startOfSegment = true;
          })
        else
          false;

    in doMatch {
      nameIdx = 0;
      patIdx = 0;
      startOfSegment = true;
      starBacktrack = null;
      doublestarBacktrack = null;
    };
}
