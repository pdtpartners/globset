{ lib }:
let
  inherit (builtins)
    length
    filter
    head
    pathExists
    readDir
    replaceStrings
    stringLength
    substring
    tail
    elemAt
  ;

  inherit (lib)
    hasInfix
    hasPrefix
    concatLists
    mapAttrsToList
    stringToCharacters
  ;

  inherit (lib.strings) concatStrings charToInt;

  inherit (lib.filesystem)
    pathType
  ;

in rec {
  findOpenBrace = str: idx:
    let len = stringLength str;
    in if idx >= len then -1
    else if substring idx 1 str == "{" && (idx == 0 || (idx > 0 && substring (idx - 1) 1 str != "\\")) then idx
    else findOpenBrace str (idx + 1);

  findCloseBrace = str: idx:
    if idx >= stringLength str then -1
    else if substring idx 1 str == "}" && (idx == 0 || (idx > 0 && substring (idx - 1) 1 str != "\\")) then idx
    else findCloseBrace str (idx + 1);
  
  findNextComma = str: idx: len:
    if idx >= len then -1
    else if substring idx 1 str == "," && 
          (idx == 0 || substring (idx - 1) 1 str != "\\") 
    then idx
    else findNextComma str (idx + 1) len;

  collectParts = str:
    let
      len = stringLength str;
      doCollect = start: parts:
        let
          nextComma = findNextComma str start len;
          segment = if start < 0 || len < 0 then ""
                  else substring start (if nextComma == -1
                                      then len - start
                                      else nextComma - start) str;
        in if nextComma == -1
          then parts ++ [segment]
          else doCollect (nextComma + 1) (parts ++ [segment]);
    in doCollect 0 [];

  parseAlternates = pattern:
    let
      openIdx = findOpenBrace pattern 0;
      closeIdx = if openIdx == -1 then -1 else findCloseBrace pattern (openIdx + 1);
    in if openIdx == -1 || closeIdx == -1 then { prefix = ""; alternates = [ pattern ]; suffix = ""; } 
    else {
      prefix = substring 0 openIdx pattern;
      suffix = substring (closeIdx + 1) (stringLength pattern - closeIdx - 1) pattern;
      alternates = collectParts (substring (openIdx + 1) (closeIdx - openIdx - 1) pattern);
    };
  
  expandAlternates = pattern:
    let
      parts = parseAlternates pattern;
      suffixVariants = if hasInfix "{" parts.suffix then expandAlternates parts.suffix else [parts.suffix];
      result = if parts.alternates == [pattern] then [pattern]
        else concatLists (map (alt: map (suffix: unescapeMeta ["{" "}" ","] (parts.prefix + alt + suffix)) suffixVariants) parts.alternates);
    in result;

  globSegments = root: pattern: firstSegment:
    let
      allAlternates = expandAlternates pattern;
    in
      concatLists (map (p: globSegments' root p firstSegment) allAlternates);

  globSegments' = root: pattern: firstSegment:
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
      escapedPattern = unescapeMeta [ "*" "[" "]" "-" ] pattern;

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
          if char == "*" || char == "[" then i
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

  unescapeMeta = chars: str:
    replaceStrings 
      (map (c: "\\" + c) chars)
      chars
      str;

  /* Function: parseCharClass
     Type: String -> Int -> { content: String, endIdx: Int, isNegated: Bool }
     Parses a character class starting at the given index. Handles
       - Simple classes [abc]
       - Ranges [a-z]
       - Negated classes [^abc] or [!abc]

     Examples:
       parseCharClass "[abc]def" 0 => { content = "abc", endIdx = 4, isNegated = false }
       parseCharClass "x[^0-9]" 1 => { content = "^0-9", endIdx = 6, isNegated = true }
  */
  parseCharClass = str: startIdx:
    let
      len = stringLength str;

      findClosingBracket = idx:
        if idx >= len then
          -1
        else
          let
            char = substring idx 1 str;
            nextChar =
              if (idx + 1) < len then substring (idx + 1) 1 str else "";
          in if char == "\\" && nextChar == "]" then
            findClosingBracket (idx + 2)
          else if char == "]" && idx > startIdx + 1 then
            idx
          else
            findClosingBracket (idx + 1);

      endIdx = findClosingBracket (startIdx + 1);
      rawContent = substring (startIdx + 1) (endIdx - startIdx - 1) str;
      firstChar = substring (startIdx + 1) 1 str;

      content =
        let chars = stringToCharacters rawContent;
        isNegation = firstChar == "^" || firstChar == "!";
        skipFirst = if isNegation then tail chars else chars;
      in concatStrings skipFirst;
    in {
      inherit content endIdx;
      isNegated = firstChar == "^" || firstChar == "!";
    };

  /* Function: matchesCharClass
     Type: String -> String -> Bool
     Checks if a character matches the given character class definition

     Examples:
      matchesCharClass "abc" "b"    => true   # Direct match
      matchesCharClass "a-z" "m"    => true   # Range match
      matchesCharClass "^0-9" "a"   => true   # Negated match
      matchesCharClass "!aeiou" "x" => true   # Alternative negation
  */
  matchesCharClass = class: char:
    let
      isNegated = hasPrefix "^" class || hasPrefix "!" class;
      actualClass = if isNegated then substring 1 (stringLength class - 1) class else class;
      chars = stringToCharacters actualClass;

      matches =
        if length chars >= 3 && elemAt chars 1 == "-" then
          inCharRange (head chars) (elemAt chars 2) char
        else
          builtins.elem char chars;
    in
      if isNegated then !matches else matches;

  /* Function: inCharRange
     Type: String -> String -> String -> Bool

     Checks if a character falls within an ASCII range using character codes.
     Used for implementing range matches like [a-z].

     Examples:
       inCharRange "a" "z" "m" => true  # m is between a-z
       inCharRange "0" "9" "5" => true  # 5 is between 0-9
       inCharRange "a" "f" "x" => false # x is outside a-f
  */
  inCharRange = start: end: char:
    let
      startCode = charToInt start;
      endCode = charToInt end;
      charCode = charToInt char;
    in charCode >= startCode && charCode <= endCode;
}
