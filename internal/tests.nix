{ lib }:

let
  inherit (builtins)
    listToAttrs
    genList
    length
    elemAt
  ;

  internal = import ./. { inherit lib; };

  mkSuite = {
    testNameFn
  , valueFn
  , tests
  }:
    listToAttrs
      (genList
        (i: let
          testCase = elemAt tests i;
          testName = testNameFn testCase;
        in {
          name = "test (${testName})";
          value = {
            expr = valueFn testCase;
            expected = testCase.expected;
          };
        })
        (length tests)
      );

in {
  decodeUtf8 = mkSuite {
    testNameFn = testCase: ''decodeUtf8 "${testCase.str}" ${toString testCase.offset}'';
    valueFn = testCase: internal.decodeUtf8 testCase.str testCase.offset;
    tests = [
      {
        str = "•foo";
        offset = 0;
        expected = "•";
      }
      {
        str = "•foo";
        offset = 3;
        expected = "f";
      }
    ];
  };
  
  lastIndexSlash = mkSuite {
    testNameFn = testCase: ''lastIndexSlash "${testCase.str}"'';
    valueFn = testCase: internal.lastIndexSlash testCase.str;
    tests = [
      { str = ""; expected = -1; }
      { str = "/"; expected = 0; }
      { str = "å/"; expected = 2; }
      { str = "∫/"; expected = 3; }
      { str = "a/b/c"; expected = 3; }
      { str = "å/b/c"; expected = 4; }
      { str = "å/∫/ç"; expected = 6; }
      { str = "a\\/b/c"; expected = 4; }
      { str = "√\\/b\\/c"; expected = -1; }
      { str = "a/b\\/"; expected = 1; }
      { str = "å/b\\/"; expected = 2; }
      { str = "a\\//b"; expected = 3; }
      { str = "\\//b"; expected = 2; }
    ];
  };

  parseCharClass = mkSuite {
    testNameFn = testCase: ''parseCharClass "${testCase.input}" ${toString testCase.startIdx}'';
    valueFn = testCase: internal.parseCharClass testCase.input testCase.startIdx;
    tests = [
      {
        input = "[abc]def";
        startIdx = 0;
        expected = {
          content = "abc";
          endIdx = 4;
          isNegated = false;
        };
      }
      {
        input = "[åbç]def";
        startIdx = 0;
        expected = {
          content = "åbç";
          endIdx = 6;
          isNegated = false;
        };
      }
      {
        input = "x[^0-9]";
        startIdx = 1;
        expected = {
          content = "0-9";
          endIdx = 6;
          isNegated = true;
        };
      }
      {
        input = "x[^º-ª]";
        startIdx = 1;
        expected = {
          content = "º-ª";
          endIdx = 8;
          isNegated = true;
        };
      }
      {
        input = "[a\\]b]";
        startIdx = 0;
        expected = {
          content = "a\\]b";
          endIdx = 5;
          isNegated = false;
        };
      }
      {
        input = "[å\\]∫]";
        startIdx = 0;
        expected = {
          content = "å\\]∫";
          endIdx = 8;
          isNegated = false;
        };
      }
      {
        input = "[\\^abc]";
        startIdx = 0;
        expected = {
          content = "\\^abc";
          endIdx = 6;
          isNegated = false;
        };
      }
      {
        input = "[\\^åbc]";
        startIdx = 0;
        expected = {
          content = "\\^åbc";
          endIdx = 7;
          isNegated = false;
        };
      }
      {
        input = "[!a-z]123";
        startIdx = 0;
        expected = {
          content = "a-z";
          endIdx = 5;
          isNegated = true;
        };
      }
      {
        input = "[!a-z]¡23";
        startIdx = 0;
        expected = {
          content = "a-z";
          endIdx = 5;
          isNegated = true;
        };
      }
      {
        input = "[^abc]";
        startIdx = 0;
        expected = {
          content = "abc";
          endIdx = 5;
          isNegated = true;
        };
      }
      {
        input = "[^a∫c]";
        startIdx = 0;
        expected = {
          content = "a∫c";
          endIdx = 7;
          isNegated = true;
        };
      }
      {
        input = "[abc";
        startIdx = 0;
        expected = {
          content = "abc";
          endIdx = -1;
          isNegated = false;
        };
      }
    ];
  };

  matchesCharClass = mkSuite {
    testNameFn = testCase: ''matchesCharClass "${testCase.class}" "${testCase.char}"'';
    valueFn = testCase: internal.matchesCharClass testCase.class testCase.char;
    tests = [
      {class = "abc"; char = "b"; expected = true;}
      {class = "abc"; char = "d"; expected = false;}
      {class = "abç"; char = "ç"; expected = true;}
      {class = "abc"; char = "ç"; expected = false;}
      {class = "a-c"; char = "c"; expected = true;}
      {class = "a-c"; char = "d"; expected = false;}
      {class = "α-ε"; char = "δ"; expected = true;}
      {class = "α-γ"; char = "δ"; expected = false;}
      {class = "^α-ε"; char = "δ"; expected = false;}
      {class = "^α-γ"; char = "δ"; expected = true;}
      {class = "!α-ε"; char = "δ"; expected = false;}
      {class = "!α-γ"; char = "δ"; expected = true;}
      {class = "^0-9"; char = "a"; expected = true;}
      {class = "^0-9"; char = "9"; expected = false;}
      {class = "!e-g"; char = "d"; expected = true;}
      {class = "!e-g"; char = "f"; expected = false;}
      {class = "^abc"; char = "d"; expected = true;}
      {class = "!abc"; char = "c"; expected = false;}
      {class = "^ab√"; char = "v"; expected = true;}
      {class = "!ab√"; char = "v"; expected = true;}
      {class = "^ab√"; char = "√"; expected = false;}
      {class = "!ab√"; char = "√"; expected = false;}
    ];
  };

  inCharRange = mkSuite {
    testNameFn = testCase: ''inCharRange "${testCase.start}" "${testCase.end}" "${testCase.char}"'';
    valueFn = testCase: internal.inCharRange testCase.start testCase.end testCase.char;
    tests = [
      {start = "a"; end = "c"; char = "b"; expected = true;}
      {start = "a"; end = "c"; char = "B"; expected = false;}
      {start = "0"; end = "9"; char = "5"; expected = true;}
      {start = "3"; end = "6"; char = "7"; expected = false;}
      {start = "3"; end = "6"; char = "6"; expected = true;}
      {start = "3"; end = "6"; char = "3"; expected = true;}
      {start = "α"; end = "ε"; char = "δ"; expected = true;}
      {start = "α"; end = "γ"; char = "δ"; expected = false;}
      {start = "←"; end = "↓"; char = "→"; expected = true;}
      {start = "가"; end = "힣"; char = "박"; expected = true;}
      {start = "あ"; end = "ん"; char = "き"; expected = true;}
      {start = "😀"; end = "😎"; char = "😄"; expected = true;}
    ];
  };

  findUnescapedChar = mkSuite {
    testNameFn = testCase: ''findUnescapedChar "${testCase.str}" "${toString testCase.idx}" "${builtins.toJSON testCase.chars}"'';
    valueFn = testCase: internal.findUnescapedChar testCase.str testCase.idx testCase.chars;
    tests = [
      { str = ""; idx = 0; chars = [ "{" ]; expected = -1; }
      { str = "{abc"; idx = 0; chars = [ "{" ]; expected = 0; }
      { str = "{abc"; idx = 1; chars = [ "{" ]; expected = -1; }
      { str = "\\{a{"; idx = 0; chars = [ "{" ]; expected = 3; }
      { str = "abc\\{def"; idx = 0; chars = [ "{" ]; expected = -1; }
      { str = "ab\\{cd{ef"; idx = 0; chars = [ "{" ]; expected = 6; }
      { str = "åb\\{cd{ef"; idx = 0; chars = [ "{" ]; expected = 7; }
      { str = "å{"; idx = 0; chars = [ "{" ]; expected = 2; }
      { str = "∫{"; idx = 0; chars = [ "{" ]; expected = 3; }
      { str = "escaped\\"; idx = 0; chars = [ "{" ]; expected = -1; }
      { str = "escaped\\\\"; idx = 0; chars = [ "{" ]; expected = -1; }
      { str = ""; idx = 0; chars = [ "}" ]; expected = -1; }
      { str = "}abc"; idx = 0; chars = [ "}" ]; expected = 0; }
      { str = "}abc"; idx = 1; chars = [ "}" ]; expected = -1; }
      { str = "\\}a}"; idx = 0; chars = [ "}" ]; expected = 3; }
      { str = "abc\\}def"; idx = 0; chars = [ "}" ]; expected = -1; }
      { str = "ab\\}cd}ef"; idx = 0; chars = [ "}" ]; expected = 6; }
      { str = "aå\\}cd}ef"; idx = 0; chars = [ "}" ]; expected = 7; }
      { str = "å}"; idx = 0; chars = [ "}" ]; expected = 2; }
      { str = "∫}"; idx = 0; chars = [ "}" ]; expected = 3; }
      { str = "escaped\\"; idx = 0; chars = [ "}" ]; expected = -1; }
      { str = "escaped\\\\"; idx = 0; chars = [ "}" ]; expected = -1; }
      { str = ""; idx = 0; chars = [ "," ]; expected = -1; }
      { str = ",abc"; idx = 0; chars = [ "," ]; expected = 0; }
      { str = ",åbc"; idx = 0; chars = [ "," ]; expected = 0; }
      { str = "abc,def"; idx = 0; chars = [ "," ]; expected = 3; }
      { str = "abå,def"; idx = 0; chars = [ "," ]; expected = 4; }
      { str = "abc\\,def"; idx = 0; chars = [ "," ]; expected = -1; }
      { str = "abc\\,def,ghi"; idx = 0; chars = [ "," ]; expected = 8; }
      { str = ""; idx = 0; chars = [ "*" "[" ]; expected = -1; }
      { str = "*abc"; idx = 0; chars = [ "*" "[" ]; expected = 0; }
      { str = "\\*a*"; idx = 0; chars = [ "*" "[" ]; expected = 3; }
      { str = "abc\\*def"; idx = 0; chars = [ "*" "[" ]; expected = -1; }
      { str = "ab\\*cd*ef"; idx = 0; chars = [ "*" "[" ]; expected = 6; }
      { str = "aå\\*cd*ef"; idx = 0; chars = [ "*" "[" ]; expected = 7; }
      { str = "no\\*meta"; idx = 0; chars = [ "*" "[" ]; expected = -1; }
      { str = "\\\\*meta"; idx = 0; chars = [ "*" "[" ]; expected = 2; }
      { str = "escaped\\"; idx = 0; chars = [ "*" "[" ]; expected = -1; }
      { str = "escaped\\\\"; idx = 0; chars = [ "*" "[" ]; expected = -1; }
    ];
  };

  collectParts = mkSuite {
    testNameFn = testCase: ''collectParts "${testCase.str}"'';
    valueFn = testCase: internal.collectParts testCase.str;
    tests = [
      { str = "a,b,c"; expected = ["a" "b" "c"]; }
      { str = "å,b,c"; expected = ["å" "b" "c"]; }
      { str = "å,b,cç,d"; expected = ["å" "b" "cç" "d"]; }
      { str = "a\\,b,c"; expected = ["a\\,b" "c"]; }
      { str = "a\\[b,c"; expected = ["a\\[b" "c"]; }
      { str = "a\\[∫,c"; expected = ["a\\[∫" "c"]; }
      { str = "a\\]b,c"; expected = ["a\\]b" "c"]; }
      { str = "a\\-b,c"; expected = ["a\\-b" "c"]; }
      { str = "a\\*b,c"; expected = ["a\\*b" "c"]; }
      { str = "a,b,[cd]"; expected = ["a" "b" "[cd]"]; }
      { str = "a\\,b,c,d\\{"; expected = ["a\\,b" "c" "d\\{"]; }
      { str = "a\\,∫,c,ƒ\\{"; expected = ["a\\,∫" "c" "ƒ\\{"]; }
      { str = "foo\\,bar,baz"; expected = ["foo\\,bar" "baz"]; }
      { str = "single"; expected = ["single"]; }
      { str = "\\,"; expected = ["\\,"]; }
      { str = "\\µ"; expected = ["\\µ"]; }
      { str = ","; expected = ["" ""]; }
    ];
  };

  expandAlternates = mkSuite {
    testNameFn = testCase: ''expandAlternates "${testCase.pattern}"'';
    valueFn = testCase: internal.expandAlternates testCase.pattern;
    tests = [
      { pattern = "{a,b}"; expected = ["a" "b"]; }
      { pattern = "{å,b}"; expected = ["å" "b"]; }
      { pattern = "{a*,b}"; expected = ["a*" "b"]; }
      { pattern = "{å*,b}"; expected = ["å*" "b"]; }
      { pattern = "{å*µ*,b}"; expected = ["å*µ*" "b"]; }
      { pattern = "{foo.[ch],test_foo.[ch]}"; expected = ["foo.[ch]" "test_foo.[ch]"]; }
      { pattern = "{foo.[çh],test_foo.[çh]}"; expected = ["foo.[çh]" "test_foo.[çh]"]; }
      { pattern = "{[x-z],b}"; expected = ["[x-z]" "b"]; }
      { pattern = "{[ƒ-√],b}"; expected = ["[ƒ-√]" "b"]; }
      { pattern = "pre{a\\,b,c}post"; expected = ["prea,bpost" "precpost"]; }
      { pattern = "foo\\{bar,baz}"; expected = ["foo\\{bar,baz}"]; }
      { pattern = "{a,b\\,c,d}"; expected = ["a" "b,c" "d"]; }
      { pattern = "{a,b\\,c,∂}"; expected = ["a" "b,c" "∂"]; }
      { pattern = "{foo,bar}.{c,h}"; expected = ["foo.c" "foo.h" "bar.c" "bar.h"]; }
      { pattern = "{foo,bar}.{ç,˙}"; expected = ["foo.ç" "foo.˙" "bar.ç" "bar.˙"]; }
      { pattern = "{,foo}"; expected = ["" "foo"]; }
      { pattern = "pre{a,b}post{1,2}"; expected = ["preapost1" "preapost2" "prebpost1" "prebpost2"]; }
    ];
  };

  parseAlternates = mkSuite {
    testNameFn = testCase: ''parseAlternates "${testCase.pattern}"'';
    valueFn = testCase: internal.parseAlternates testCase.pattern;
    tests = [
      { pattern = "{a,b}"; expected = { prefix = ""; alternates = ["a" "b"]; suffix = ""; }; }
      { pattern = "{å,b}"; expected = { prefix = ""; alternates = ["å" "b"]; suffix = ""; }; }
      { pattern = "{ßå,b}"; expected = { prefix = ""; alternates = ["ßå" "b"]; suffix = ""; }; }
      { pattern = "{ßå,b,√∫˜}"; expected = { prefix = ""; alternates = ["ßå" "b" "√∫˜"]; suffix = ""; }; }
      { pattern = "pre{a\\,b,c}post"; expected = { prefix = "pre"; alternates = ["a\\,b" "c"]; suffix = "post"; }; }
      { pattern = "pre{a\\,∫,c}pos†"; expected = { prefix = "pre"; alternates = ["a\\,∫" "c"]; suffix = "pos†"; }; }
      { pattern = "foo\\{bar,baz}"; expected = { prefix = ""; alternates = ["foo\\{bar,baz}"]; suffix = ""; }; }
      { pattern = "{a,b\\,c,d}"; expected = { prefix = ""; alternates = ["a" "b\\,c" "d"]; suffix = ""; }; }
      { pattern = "{å,b\\,ç,d}"; expected = { prefix = ""; alternates = ["å" "b\\,ç" "d"]; suffix = ""; }; }
    ];
  };

  match = mkSuite {
    testNameFn = testCase: ''match "${testCase.pattern}" "${testCase.path}"'';
    valueFn = testCase: lib.globset.match testCase.pattern testCase.path;
    tests = [
      # Single glob
      { pattern = "*"; path = ""; expected = true; }
      { pattern = "*"; path = "/"; expected = false; }
      { pattern = "/*"; path = "/"; expected = true; }
      { pattern = "/*"; path = "/debug/"; expected = false; }
      { pattern = "/*"; path = "//"; expected = false; }
      { pattern = "abc"; path = "abc"; expected = true; }
      { pattern = "åbc"; path = "åbc"; expected = true; }
      { pattern = "*"; path = "abc"; expected = true; }
      { pattern = "*c"; path = "abc"; expected = true; }
      { pattern = "*ç"; path = "abç"; expected = true; }
      { pattern = "*/"; path = "a/"; expected = true; }
      { pattern = "a*"; path = "a"; expected = true; }
      { pattern = "a*"; path = "abc"; expected = true; }
      { pattern = "a*"; path = "ab/c"; expected = false; }
      { pattern = "a*/b"; path = "abc/b"; expected = true; }
      { pattern = "å*/b"; path = "åbc/b"; expected = true; }
      { pattern = "a*/b"; path = "a/c/b"; expected = false; }
      { pattern = "a*/c/"; path = "a/b"; expected = false; }
      { pattern = "a*b*c*d*e*"; path = "axbxcxdxe"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxe/f"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxexxx/f"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxe/xxx/f"; expected = false; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxexxx/fff"; expected = false; }
      { pattern = "a\\*b"; path = "ab"; expected = false; }
      { pattern = "å\\*∫*"; path = "å∫¡™£"; expected = false; }

      # Globstar / doublestar
      { pattern = "**"; path = ""; expected = true; }
      { pattern = "a/**"; path = "a"; expected = true; }
      { pattern = "å/**"; path = "å"; expected = true; }
      { pattern = "a/**/"; path = "a"; expected = true; }
      { pattern = "a/**"; path = "a/"; expected = true; }
      { pattern = "a/**/"; path = "a/"; expected = true; }
      { pattern = "a/**"; path = "a/b"; expected = true; }
      { pattern = "a/**"; path = "a/b/c"; expected = true; }
      { pattern = "**/c"; path = "c"; expected = true; }
      { pattern = "**/c"; path = "b/c"; expected = true; }
      { pattern = "**/c"; path = "a/b/c"; expected = true; }
      { pattern = "**/ç"; path = "a/b/ç"; expected = true; }
      { pattern = "**/c"; path = "a/b"; expected = false; }
      { pattern = "**/c"; path = "abcd"; expected = false; }
      { pattern = "**/c"; path = "a/abc"; expected = false; }
      { pattern = "a/**/b"; path = "a/b"; expected = true; }
      { pattern = "å/**/∫"; path = "å/∫"; expected = true; }
      { pattern = "a/**/c"; path = "a/b/c"; expected = true; }
      { pattern = "a/**/d"; path = "a/b/c/d"; expected = true; }
      { pattern = "a/**/d"; path = "a/∫/ç/d"; expected = true; }
      { pattern = "a/\\**"; path = "a/b/c"; expected = false; }

      # Character Class
      {
        pattern = "[abc]";
        path = "b";
        expected = true;
      }
      {
        pattern = "[abc]";
        path = "d";
        expected = false;
      }
      {
        pattern = "[abç]";
        path = "ç";
        expected = true;
      }
      {
        pattern = "[abç]";
        path = "d";
        expected = false;
      }
      {
        pattern = "[α-θ]";
        path = "θ";
        expected = true;
      }
      {
        pattern = "[α-θ]";
        path = "ω";
        expected = false;
      }
      {
        pattern = "[^α-θ]";
        path = "θ";
        expected = false;
      }
      {
        pattern = "[^α-θ]";
        path = "ω";
        expected = true;
      }
      {
        pattern = "[!α-θ]";
        path = "θ";
        expected = false;
      }
      {
        pattern = "[!α-θ]";
        path = "ω";
        expected = true;
      }
      {
        pattern = "[^abc]";
        path = "d";
        expected = true;
      }
      {
        pattern = "[^abc]";
        path = "b";
        expected = false;
      }
      {
        pattern = "[!0-9]";
        path = "a";
        expected = true;
      }
      {
        pattern = "[!0-9]";
        path = "5";
        expected = false;
      }
      {
        pattern = "foo[abc].txt";
        path = "fooa.txt";
        expected = true;
      }
      {
        pattern = "[a-z]/**/*.txt";
        path = "d/foo/bar.txt";
        expected = true;
      }
      {
        pattern = "*.[ch]";
        path = "foo.c";
        expected = true;
      }
      {
        pattern = "*.[ch]";
        path = "foo.o";
        expected = false;
      }
      {
        pattern = "[^a-e][!p-r]o.c";
        path = "foo.c";
        expected = true;
      }
      {
        pattern = "f[\\-].c";
        path = "f-.c";
        expected = true;
      }
      {
        pattern = "f[\\[\\]].c";
        path = "f[.c";
        expected = true;
      }
      {
        pattern = "f[\\[\\]].c";
        path = "f].c";
        expected = true;
      }
      {
        pattern = "ƒ[\\[\\]].ç";
        path = "ƒ].ç";
        expected = true;
      }
      {
        pattern = "[ef]\\*.c";
        path = "f*.c";
        expected = true;
      }
      {
        pattern = "[´f]\\*.c";
        path = "´*.c";
        expected = true;
      }
    ];
  };
}
