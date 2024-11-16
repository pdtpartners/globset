{ lib }:
let
  inherit (builtins)
    elemAt
    length
  ;

  inherit (lib)
    concatStrings
    foldl'
    hasPrefix
    removePrefix
    sublist
    utf8
  ;

  fs = lib.fileset;

  internal = import ./internal {
    lib = lib // { inherit globset; };
  };

  globset = {
    # The file set containing all files that match any of the given glob patterns,
    # starting from the specified root directory.
    #
    # This function processes a list of glob patterns, which can include negative
    # patterns starting with `!` to exclude files from the resulting set. Patterns
    # are applied in order, with exclusions overriding previous inclusions. Negative
    # patterns must come after the positive patterns they are meant to exclude.
    #
    # This is similar to the Unix shell globbing mechanism but extended to support
    # negative patterns for exclusions.
    #
    # Type:
    #   globs :: Path -> [ String ] -> FileSet
    #
    # Example:
    #   # Collect files matching patterns in the `src` directory
    #   globs ./src [
    #     "**/*.c"          # Include all C source files
    #     "**/*.h"          # Include all header files
    #     "!**/test_*"      # Exclude test files
    #   ]
    globs = root: patterns:
      let
        applyPattern = acc: pattern:
          if hasPrefix "!" pattern then
            fs.difference acc (globset.glob root (removePrefix "!" pattern))
          else
            fs.union acc (globset.glob root pattern);

      in foldl' applyPattern (fs.unions []) patterns;

    # The file set containing all files that match the given glob pattern, starting
    # from the specified root directory.
    #
    # This function expands the glob pattern relative to the root directory and
    # returns a file set of the matching files.
    #
    # Type:
    #   glob :: Path -> String -> FileSet
    #
    # Example:
    #   # Collect all Python files in the `scripts` directory
    #   glob ./scripts "**/*.py"
    #
    # See also:
    #   - [Pattern matching](https://en.wikipedia.org/wiki/Glob_(programming)).
    glob = root: pattern:
      fs.unions
        (map
          (name: root + "/${name}")
          (internal.globSegments root (utf8.chars pattern) true)
        );

    # Determines whether a given file name matches a glob pattern.
    #
    # This function supports single `*` wildcards matching any sequence of characters
    # except directory separators, double `**` wildcards matching any sequence of
    # characters including directory separators, and escaping of meta characters
    # using backslashes.
    #
    # This is useful for testing patterns against file names or paths.
    #
    # Type:
    #   match :: String -> String -> Bool
    #
    # Examples:
    #   match "a*/b" "abc/b"  # Returns true
    #   match "a*/b" "a/c/b"  # Returns false
    #   match "**/c" "a/b/c"  # Returns true
    #   match "**/c" "a/b"    # Returns false
    #   match "a\\*b" "ab"    # Returns false
    #   match "a\\*b" "a*b"   # Returns true
    match = pattern: name:
      let
        patternChars = utf8.chars pattern;
        nameChars = utf8.chars name;

        patLen = length patternChars;

        nameLen = length nameChars;

        isSeparator = char: char == "/";

        doMatch = {
          nameIdx, patIdx, startOfSegment, starBacktrack, doublestarBacktrack
        }@args:
          if nameIdx >= nameLen then
            internal.isZeroLengthPattern
              (concatStrings (sublist patIdx (patLen - patIdx) patternChars))
          else if patIdx >= patLen then
            handleBacktrack args
          else
            let
              nameChar = elemAt nameChars nameIdx;

              patChar = elemAt patternChars patIdx;

              isStar = patChar == "*";

              isQmark = patChar == "?";

              isEscape = patChar == "\\";

            in
              if isStar then
                handleStar args
              else if isEscape && ((patIdx + 1) >= patLen) then
                # todo: ErrBadPattern
                false
              else if isEscape && elemAt patternChars (patIdx + 1) == nameChar then
                doMatch (args // {
                  nameIdx = nameIdx + 1;
                  patIdx = patIdx + 2;
                  startOfSegment = isSeparator patChar;
                })
              else if patChar == nameChar || (isQmark && !(isSeparator nameChar)) then
                doMatch (args // {
                  nameIdx = nameIdx + 1;
                  patIdx = patIdx + 1;
                  startOfSegment = isSeparator patChar;
                })
              else
                handleBacktrack args;

        handleStar = args:
          let
            # Check ahead for a second '*'.
            nextPatIdx = args.patIdx + 1;

            isDoublestar = nextPatIdx < patLen && elemAt patternChars nextPatIdx == "*";

            starBacktrack = {
              inherit (args) nameIdx;
              # Doublestar must begin with separator, otherwise we're going to
              # treat it like a single star like bash.
              patIdx = nextPatIdx + (if isDoublestar then 1 else 0);
            };

            # Doublestar must also end with separator, treating as single star.
            doublestarAfterChar = elemAt patternChars (nextPatIdx + 1);

            doublestarBacktrack = {
              inherit (args) nameIdx;
              # Add two to be after the separator.
              # e.g. '**/?' where nextPatIdx is index of '?'.
              patIdx = nextPatIdx + 2;
            };

          in
            if isDoublestar && args.startOfSegment && nextPatIdx + 1 >= patLen then
              # Pattern ends in `/**`, return true.
              true
            else if isDoublestar && args.startOfSegment && isSeparator doublestarAfterChar then
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

            starNameChar = elemAt nameChars args.starBacktrack.nameIdx;

            nextSeparatorIdx =
              internal.findNextSeparator nameChars args.doublestarBacktrack.nameIdx;

            doublestarBacktrack = {
              inherit (args.doublestarBacktrack) patIdx;
              nameIdx = nextSeparatorIdx + 1;
            };

          in
            if args.starBacktrack != null && !isSeparator starNameChar then
              doMatch (args // {
                inherit starBacktrack;
                inherit (starBacktrack) nameIdx;
                patIdx = args.starBacktrack.patIdx;
                startOfSegment = false;
              })
            else if args.doublestarBacktrack != null && nextSeparatorIdx != -1  then
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
  };

in globset
