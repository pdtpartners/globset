{ lib }:
let
  inherit (builtins)
    head replaceStrings stringLength substring tail pathExists match elemAt
    length concatMap elem filter;

  inherit (lib)
    stringToCharacters hasPrefix hasInfix removePrefix splitString take drop;
  inherit (lib.strings) charToInt concatStrings;
  inherit (lib.filesystem) pathType;
  inherit (lib.lists) concatLists;

  asciiLowerA = 97;
  asciiLowerZ = 122;

in rec {
  /* Function: findEscapedChar
     Type: [String] -> Int -> String -> Bool
     Checks if a specific character is escaped by a backslash sequence
  */
  findEscapedChar = chars: idx: expectedChar:
    let
      len = length chars;
      prevIdx = idx - 1;
    in if prevIdx < 0 || idx >= len then
      false
    else
      (elemAt chars prevIdx) == "\\" && (elemAt chars idx) == expectedChar;

  /* Function: splitUnescaped
     Type: String -> [String]
     Splits string on unescaped commas while preserving escaped ones
  */
  splitUnescaped = str:
    let
      chars = stringToCharacters str;

      collectPart = chars: current: parts:
        if chars == [ ] then
          parts ++ [ current ]
        else
          let
            char = head chars;
            rest = tail chars;
          in if char == "\\" && rest != [ ] then
            collectPart (tail rest) (current + char + (head rest)) parts
          else if char == "," && !(findEscapedChar chars 0 ",") then
            collectPart rest "" (parts ++ [ current ])
          else
            collectPart rest (current + char) parts;
    in (collectPart chars "" [ ]);

  /* Function: parseAlternates
     Type: String -> { prefix: String, alternates: [String], suffix: String }
     Parses a pattern containing alternates into its components.

     Example:
     "{foo},{bar}.{c,h}" ->
     {
       prefix = "";
       alternates = ["foo" "bar"];
       suffix = ".{c,h}";
     }
  */
  parseAlternates = pattern:
    let
      chars = stringToCharacters pattern;

      findOpen = chars: idx:
        if chars == [ ] then
          -1
        else if head chars == "{" && !findEscapedChar chars idx "{" then
          idx
        else
          findOpen (tail chars) (idx + 1);

      findClose = chars: idx: depth:
        if chars == [ ] then
          -1
        else if head chars == "}" && depth == 1
        && !findEscapedChar chars idx "}" then
          idx
        else if head chars == "{" && !findEscapedChar chars idx "{" then
          findClose (tail chars) (idx + 1) (depth + 1)
        else if head chars == "}" && !findEscapedChar chars idx "}" then
          findClose (tail chars) (idx + 1) (depth - 1)
        else
          findClose (tail chars) (idx + 1) depth;

      openIdx = findOpen chars 0;
      noAlternates = openIdx == -1;
      closeIdx = if noAlternates then
        -1
      else
        findClose (drop (openIdx + 1) chars) (openIdx + 1) 1;

      invalidPattern = closeIdx == -1;
    in if noAlternates || invalidPattern then {
      prefix = "";
      alternates = [ pattern ];
      suffix = "";
    } else
      let
        prefix = substring 0 openIdx pattern;
        content = substring (openIdx + 1) (closeIdx - openIdx - 1) pattern;
        alternates = splitUnescaped content;
        suffix = substring (closeIdx + 1) (stringLength pattern - closeIdx - 1)
          pattern;
      in { inherit prefix alternates suffix; };

  /* Function: expandAlternates
     Type: String -> [String]
     Expands a pattern with alternates into all possible combinations.

     Example:
     "{foo},{bar}.{c,h}" ->
     [
       "foo.c"
       "foo.h"
       "bar.c"
       "bar.h"
     ]
  */
  expandAlternates = pattern:
    let
      noAlts = !hasInfix "{" pattern || pattern == "";
      components = parseAlternates pattern;

      suffixVariants = if hasInfix "{" components.suffix then
        expandAlternates components.suffix
      else
        [ components.suffix ];

      expandOne = alt:
        map (suffix: unescapeAlternates "${components.prefix}${alt}${suffix}")
        suffixVariants;

    in if noAlts then
      [ pattern ]
    else
      concatMap expandOne components.alternates;

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
    replaceStrings [ "\\*" "\\[" "\\]" "\\{" "\\}" "\\," ] [
      "*"
      "["
      "]"
      "{"
      "}"
      ","
    ] pattern;

  /* Function: unescapeAlternates
      Type: String -> String
      Unescapes meta characters in a pattern string during alternate expansion. At this stage, we don't want to unescape *, [ and ]
  */
  unescapeAlternates = pattern:
    replaceStrings [ "\\{" "\\}" "\\," ] [ "{" "}" "," ] pattern;

  /* Function: isZeroLengthPattern
      Type: String -> Bool
      Determines if a pattern effectively matches zero-length strings.
  */
  isZeroLengthPattern = pattern:
    pattern == "" || pattern == "*" || pattern == "**" || pattern == "/**"
    || pattern == "**/" || pattern == "/**/";
}
