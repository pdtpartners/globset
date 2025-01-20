{ lib }:
let
  inherit (builtins)
    head replaceStrings stringLength substring tail pathExists match elemAt
    length;

  inherit (lib) stringToCharacters hasPrefix removePrefix;
  inherit (lib.strings) charToInt concatStrings;
  inherit (lib.filesystem) pathType;

  asciiLowerA = 97;
  asciiLowerZ = 122;

in rec {
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

      processContent = str:
        let
          chars = stringToCharacters str;
          process = chars:
            if chars == [ ] then
              [ ]
            else if head chars == "\\" && tail chars != [ ] then
              [ (head (tail chars)) ] ++ (process (tail (tail chars)))
            else
              [ (head chars) ] ++ (process (tail chars));
        in concatStrings (process (stringToCharacters str));

      rawContent = substring (startIdx + 1) (endIdx - startIdx - 1) str;
      content = processContent rawContent;
      firstChar = substring (startIdx + 1) 1 str;
    in {
      inherit content endIdx;
      isNegated = firstChar == "^" || firstChar == "!";
    };

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
      actualClass =
        if isNegated then substring 1 (stringLength class - 1) class else class;

      chars = stringToCharacters actualClass;
      matches = if length chars < 3 then
        builtins.elem char chars
      else if elemAt chars 1 == "-" then
        inCharRange (head chars) (elemAt chars 2) char
      else
        builtins.elem char chars;
      debug = builtins.trace
        "Testing ${char} against ${class} (matches: ${toString matches})" null;
    in if isNegated then !matches else matches;

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
      Returns index of first unescaped meta character (* or [) or -1 if none found.
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
          in if char == "*" || char == "[" then
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
  unescapeMeta = pattern:
    replaceStrings [ "\\*" "\\[" "\\]" ] [ "*" "[" "]" ] pattern;

  /* Function: isZeroLengthPattern
      Type: String -> Bool
      Determines if a pattern effectively matches zero-length strings.
  */
  isZeroLengthPattern = pattern:
    pattern == "" || pattern == "*" || pattern == "**" || pattern == "/**"
    || pattern == "**/" || pattern == "/**/";
}
