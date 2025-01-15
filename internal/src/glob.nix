{ lib }:
let
  inherit (builtins) filter pathExists readDir substring stringLength;

  inherit (lib) concatLists mapAttrsToList hasPrefix removePrefix foldl';

  inherit (lib.filesystem) pathType;

  fs = lib.fileset;

  pattern = import ./pattern.nix { inherit lib; };
  path = import ./path.nix { inherit lib; };
  inherit (import ./match.nix { inherit lib; }) match;

in rec {
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
          fs.difference acc (glob root (removePrefix "!" pattern))
        else
          fs.union acc (glob root pattern);

    in foldl' applyPattern (fs.unions [ ]) patterns;

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
    fs.unions (map (name: root + "/${name}") (globSegments root pattern true));

  /* Function: globSegments
     	Type: Path -> String -> Bool -> [String]
     	Core globbing function that processes patterns and returns matching paths.
  */
  globSegments = root: pattern': firstSegment:
    let
      patternStart = pattern.firstUnescapedMeta pattern';
      splitIndex = path.lastIndexSlash pattern';

      dir = if splitIndex == -1 then "" else substring 0 splitIndex pattern';

      pattern'' = if splitIndex == -1 then
        pattern'
      else
        substring (splitIndex + 1) (stringLength pattern') pattern';

    in if patternStart == -1 then
      pattern.handleNoMeta root pattern' firstSegment
    else if firstSegment && pattern' == "**" then
      [ "" ]
    else if splitIndex <= patternStart then
      globSegment root dir pattern'' firstSegment
    else
      concatLists (map (dir: globSegment root dir pattern'' firstSegment)
        (globSegments root dir false));

  /* Function: globSegment
     	Type: Path -> String -> String -> Bool -> [String]
     	Matches a single segment of a path against a pattern.
  */
  globSegment = root: dir: pattern': matchFiles:
    if pattern' == "" then
      if matchFiles then [ ] else [ dir ]
    else if pattern' == "**" then
      globDoublestar root dir matchFiles
    else if pathType (root + "/${dir}") != "directory" then
      [ ]
    else
      let
        matchFileType = file:
          if matchFiles then
            file.type == "regular"
          else
            file.type == "directory";

        onlyMatches = file: matchFileType file && match pattern' file.name;

        files = mapAttrsToList (name: type: { inherit name type; })
          (readDir (root + "/${dir}"));

      in map (file: "${dir}/${file.name}") (filter onlyMatches files);

  /* Function: globDoublestar
     	Type: Path -> String -> Bool -> [String]
     	Handles recursive directory matching for ** patterns.
  */
  globDoublestar = root: dir: matchFiles:
    let
      doGlob = root: dir: canMatchFiles:
        let
          processEntry = name: type:
            if type == "directory" then
              doGlob root "${dir}/${name}" canMatchFiles
            else if canMatchFiles && type == "regular" then
              [ "${dir}/${name}" ]
            else
              [ ];

          matchesInSubdirs = concatLists
            (mapAttrsToList processEntry (readDir (root + "/${dir}")));

        in [ dir ] ++ matchesInSubdirs;

    in doGlob root dir matchFiles;
}
