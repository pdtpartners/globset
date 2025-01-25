{ lib }:
let
  inherit (builtins)
    stringLength
    substring
  ;

  inherit (lib)
    foldl'
    hasPrefix
    removePrefix
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
      let segments = internal.globSegments root pattern true;
      in if segments == [ ] then
        fs.unions [ ]
      else
        fs.unions (map (name: root + "/${name}") segments);

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
        patLen = stringLength pattern;

        nameLen = stringLength name;

        charAt = str: i: substring i 1 str;

        isSeparator = char: char == "/";

        doMatch = {
          nameIdx, patIdx, startOfSegment, starBacktrack, doublestarBacktrack
        }@args:
          if nameIdx >= nameLen then
            internal.isZeroLengthPattern
              (substring patIdx (patLen - patIdx) pattern)
          else if patIdx >= patLen then
            handleBacktrack args
          else
            let
              nameChar = charAt name nameIdx;
              patChar = charAt pattern patIdx;
              isStar = patChar == "*";
              isEscape = patChar == "\\";
              isClass = patChar == "[";
              nextPatChar = if (patIdx + 1) < patLen then charAt pattern (patIdx + 1) else "";
            in
              if isStar then
                handleStar args
              else if isClass then
                handleCharClass args
              else if isEscape then
                if nextPatChar == "" then
                  # todo: ErrBadPattern
                  false
                else if nextPatChar == nameChar then
                  doMatch (args // {
                    nameIdx = nameIdx + 1;
                    patIdx = patIdx + 2;
                    startOfSegment = isSeparator nameChar;
                  })
                else
                  handleBacktrack args
              else if patChar == nameChar then
                doMatch (args // {
                  nameIdx = nameIdx + 1;
                  patIdx = patIdx + 1;
                  startOfSegment = isSeparator patChar;
                })
              else
                handleBacktrack args;

        /* Function: handleCharClass
           Type: args -> { nameIdx: Int, patIdx: Int, startOfSegment: Bool }
           Handles character class pattern matching ([abc], [a-z], [^abc], [!0-9]).
           Called when a '[' character is encountered in the pattern.

           Examples:
             Pattern: "src/[fl]*.c" matches "src/foo.c", "src/lib.c"
        */
        handleCharClass = args:
          let
            classInfo = internal.parseCharClass pattern args.patIdx;
            matches = internal.matchesCharClass classInfo.content
              (charAt name args.nameIdx);
          in if (if classInfo.isNegated then !matches else matches) then
            doMatch (args // {
              nameIdx = args.nameIdx + 1;
              patIdx = classInfo.endIdx + 1;
              startOfSegment = false;
            })
          else
            handleBacktrack args;

        handleStar = args:
          let
            # Check ahead for a second '*'.
            nextPatIdx = args.patIdx + 1;

            isDoublestar = nextPatIdx < patLen && charAt pattern nextPatIdx == "*";

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

            starNameChar = charAt name args.starBacktrack.nameIdx;

            nextSeparatorIdx =
              internal.findNextSeparator name args.doublestarBacktrack.nameIdx;

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
