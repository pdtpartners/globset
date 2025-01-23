{ lib }:
let
  inherit (builtins)
    filter
    head
    pathExists
    readDir
    replaceStrings
    stringLength
    substring
    tail
  ;

  inherit (lib)
    concatLists
    mapAttrsToList
    stringToCharacters
  ;

  inherit (lib.filesystem)
    pathType
  ;

in rec {
  globSegments = root: pattern: firstSegment:
    let
      patternStart = firstUnescapedMeta pattern;

      splitIndex = lastIndexSlash pattern;

      dir =
        if splitIndex == -1 then ""
        else substring 0 splitIndex pattern;

      pattern' =
        if splitIndex == -1 then pattern
        else substring (splitIndex + 1) (stringLength pattern) pattern;

    in
      if patternStart == -1 then
        handleNoMeta root pattern firstSegment
      else if firstSegment && pattern == "**" then
        [ "" ]
      else if splitIndex <= patternStart then
        globSegment root dir pattern' firstSegment
      else
        concatLists (
          map
            (dir: globSegment root dir pattern' firstSegment)
            (globSegments root dir false)
        );

  handleNoMeta = root: pattern: firstSegment:
    let
      # If pattern doesn't contain any meta characters, unescape the
      # escaped meta characters.
      escapedPattern = unescapeMeta pattern;

      escapedPath = root + "/${escapedPattern}";

      isDirectory = (pathType escapedPath) == "directory";

    in
      if pathExists escapedPath && (!firstSegment || !isDirectory) then
        [ escapedPattern ]
      else
        [];

  globSegment = root: dir: pattern: matchFiles:
    let path = root + "/${dir}";
    in if pattern == "" then
      if matchFiles then []
      else [ dir ]
    else if pattern == "**" then
      globDoublestar root dir matchFiles
    else if !pathExists path || pathType path != "directory" then
      []
    else
      let
        matchFileType = file:
          if matchFiles then file.type == "regular"
          else file.type == "directory";

        onlyMatches = file:
          matchFileType file && lib.globset.match pattern file.name;

        files = mapAttrsToList
          (name: type: { inherit name type; })
          (readDir path);

      in map (file: "${dir}/${file.name}") (filter onlyMatches files);

  globDoublestar = root: dir: matchFiles:
    let
      doGlob = root: dir: canMatchFiles:
        let path = root + "/${dir}";
        in if !pathExists path || pathType path != "directory" then
          [ ]
        else let
          processEntry = name: type:
            if type == "directory" then
              doGlob root "${dir}/${name}" canMatchFiles
            else if canMatchFiles && type == "regular" then
              [ "${dir}/${name}" ]
            else
              [];

          matchesInSubdirs = concatLists (
            mapAttrsToList
              processEntry
              (readDir path)
          );

        in [ dir ] ++ matchesInSubdirs;

    in doGlob root dir matchFiles;

  isZeroLengthPattern = pattern:
    pattern == ""
    || pattern == "*"
    || pattern == "**"
    || pattern == "/**"
    || pattern == "**/"
    || pattern == "/**/";

  firstUnescapedMeta = str:
    let
      chars = stringToCharacters str;

      find = i: chars:
        if chars == [] then -1
        else let
          char = head chars;
          rest = tail chars;
        in
          if char == "*" then i
          else if char == "\\" then
            if rest == [] then -1
            else find (i + 2) (tail rest)
          else find (i + 1) rest;

    in find 0 chars;
      
  lastIndexSlash = str:
    let
      len = stringLength str;

      isUnescapedSlash = i:
        (substring i 1 str == "/") &&
        (i == 0 || substring (i - 1) 1 str != "\\");

      findLastSlash = i:
        if i < 0 then -1
        else if isUnescapedSlash i then i
        else findLastSlash (i - 1);

    in findLastSlash (len - 1);

  findNextSeparator = str: startIdx:
    let
      len = stringLength str;

      findSeparator = i:
        if i >= len then -1
        else if substring i 1 str == "/" then i
        else findSeparator (i + 1);

    in findSeparator startIdx;

  unescapeMeta = str:
    replaceStrings
      [ "\\*" ]
      [ "*" ]
      str;
}
