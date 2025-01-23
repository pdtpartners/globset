{ lib }:
let inherit (builtins) stringLength substring;

in {
  /* Function: lastIndexSlash
      Type: String -> Int
      Returns index of last unescaped forward slash or -1 if none found.
  */
  lastIndexSlash = str:
    let
      len = stringLength str;

      isUnescapedSlash = i:
        (substring i 1 str == "/")
        && (i == 0 || substring (i - 1) 1 str != "\\");

      findLastSlash = i:
        if i < 0 then
          -1
        else if isUnescapedSlash i then
          i
        else
          findLastSlash (i - 1);
    in findLastSlash (len - 1);

  /* Function: findNextSeparator
      Type: String -> Int -> Int
      Finds the next path separator starting from given index.
  */
  findNextSeparator = str: startIdx:
    let
      len = stringLength str;

      findSeparator = i:
        if i >= len then
          -1
        else if substring i 1 str == "/" then
          i
        else
          findSeparator (i + 1);

    in findSeparator startIdx;
}
