{ lib }:
let
  inherit (builtins)
    elemAt
    filter
    head
    length
    pathExists
    readDir
    replaceStrings
    tail
  ;

  inherit (lib)
    concatLists
    concatStrings
    drop
    mapAttrsToList
    take
  ;

  inherit (lib.filesystem)
    pathType
  ;

in rec {
  globSegments = root: patternChars: firstSegment:
    let
      patternStart = firstUnescapedMeta patternChars;

      splitIndex = lastIndexSlash patternChars;

      dirChars =
        if splitIndex == -1 then []
        else take splitIndex patternChars;

      patternChars' =
        if splitIndex == -1 then patternChars
        else drop (splitIndex + 1) patternChars;

    in
      if patternStart == -1 then
        handleNoMeta root (concatStrings patternChars) firstSegment
      else if firstSegment && patternChars == [ "*" "*" ] then
        [ "" ]
      else if splitIndex <= patternStart then
        globSegment root (concatStrings dirChars) patternChars' firstSegment
      else
        concatLists (
          map
            (dir: globSegment root dir patternChars' firstSegment)
            (globSegments root dirChars false)
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

  globSegment = root: dir: patternChars: matchFiles:
    if patternChars == [] then
      if matchFiles then []
      else [ dir ]
    else if patternChars == [ "*" "*" ] then
      globDoublestar root dir matchFiles
    else if pathType (root + "/${dir}") != "directory" then
      []
    else
      let
        matchFileType = file:
          if matchFiles then file.type == "regular"
          else file.type == "directory";

        onlyMatches = file:
          matchFileType file && lib.globset.match (concatStrings patternChars) file.name;

        files = mapAttrsToList
          (name: type: { inherit name type; })
          (readDir (root + "/${dir}"));

      in map (file: "${dir}/${file.name}") (filter onlyMatches files);

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
              [];

          matchesInSubdirs = concatLists (
            mapAttrsToList
              processEntry
              (builtins.readDir (root + "/${dir}"))
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

  firstUnescapedMeta = chars:
    let
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
      
  lastIndexSlash = chars:
    let
      len = length chars;

      isUnescapedSlash = i:
        (elemAt chars i == "/") &&
        (i == 0 || elemAt chars (i - 1) != "\\");

      findLastSlash = i:
        if i < 0 then -1
        else if isUnescapedSlash i then i
        else findLastSlash (i - 1);

    in findLastSlash (len - 1);

  findNextSeparator = chars: startIdx:
    let
      len = length chars;

      findSeparator = i:
        if i >= len then -1
        else if elemAt chars i == "/" then i
        else findSeparator (i + 1);

    in findSeparator startIdx;

  unescapeMeta = str:
    replaceStrings
      [ "\\*" ]
      [ "*" ]
      str;
}
