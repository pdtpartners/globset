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
    elem
    elemAt
  ;

  inherit (lib)
    utf8
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
  decodeUtf8 = str: offset:
    let
      remaining = substring offset (stringLength str - offset) str;
    in
      head (utf8.chars remaining);

  findUnescapedChar = str: idx: chars:
    let
      find = i:
        if i >= stringLength str then -1
        else
          let
            curChar = decodeUtf8 str i;
            prevPrevChar = if i > 1 then decodeUtf8 str (i - 2) else "";
            prevChar = if i > 0 then decodeUtf8 str (i - 1) else "";
            isEscaped = prevChar == "\\" && prevPrevChar != "\\";
          in
            if elem curChar chars && !isEscaped then i
            else find (i + 1);
    in find idx;

  collectParts = str:
    let
      len = stringLength str;
      doCollect = start: parts:
        let
          nextComma = findUnescapedChar str start [ "," ];
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
      openIdx = findUnescapedChar pattern 0 [ "{" ];
      closeIdx = if openIdx == -1 then -1 else findUnescapedChar pattern (openIdx + 1) [ "}" ];
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
      patternStart = findUnescapedChar pattern 0 [ "*" "[" ];

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
      
  lastIndexSlash = str:
    let
      len = stringLength str;

      isUnescapedSlash = i:
        (decodeUtf8 str i == "/") &&
        (i == 0 || decodeUtf8 str (i - 1) != "\\");

      findLastSlash = i:
        if i < 0 then -1
        else if isUnescapedSlash i then i
        else findLastSlash (i - 1);

    in findLastSlash (len - 1);

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
      endIdx = findUnescapedChar str (startIdx + 1) [ "]" ];
      rawContent = substring (startIdx + 1) (endIdx - startIdx - 1) str;
      firstChar = decodeUtf8 str (startIdx + 1);

      content =
        let chars = utf8.chars rawContent;
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
      matchesCharClass "abç" "ç"    => true   # Direct utf-8 match
      matchesCharClass "a-z" "m"    => true   # Range match
      matchesCharClass "^0-9" "a"   => true   # Negated match
      matchesCharClass "!aeiou" "x" => true   # Alternative negation
  */
  matchesCharClass = class: char:
    let
      isNegated = hasPrefix "^" class || hasPrefix "!" class;
      actualClass = if isNegated then substring 1 (stringLength class - 1) class else class;
      chars = utf8.chars actualClass;

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
      compareChars = a: b:
        let
          seqA = utf8.chars a;
          seqB = utf8.chars b;
        in builtins.lessThan seqA seqB || seqA == seqB;
    in compareChars start char && compareChars char end;
}
