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
        input = "x[^0-9]";
        startIdx = 1;
        expected = {
          content = "0-9";
          endIdx = 6;
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
        input = "[\\^abc]";
        startIdx = 0;
        expected = {
          content = "\\^abc";
          endIdx = 6;
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
        input = "[^abc]";
        startIdx = 0;
        expected = {
          content = "abc";
          endIdx = 5;
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
      {class = "a-c"; char = "c"; expected = true;}
      {class = "a-c"; char = "d"; expected = false;}
      {class = "^0-9"; char = "a"; expected = true;}
      {class = "^0-9"; char = "9"; expected = false;}
      {class = "!e-g"; char = "d"; expected = true;}
      {class = "!e-g"; char = "f"; expected = false;}
      {class = "^abc"; char = "d"; expected = true;}
      {class = "!abc"; char = "c"; expected = false;}
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
    ];
  };

  firstUnescapedMeta = mkSuite {
    testNameFn = testCase: ''firstUnescapedMeta "${testCase.str}"'';
    valueFn = testCase: internal.firstUnescapedMeta testCase.str;
    tests = [
      { str = ""; expected = -1; }
      { str = "*abc"; expected = 0; }
      { str = "\\*a*"; expected = 3; }
      { str = "abc\\*def"; expected = -1; }
      { str = "ab\\*cd*ef"; expected = 6; }
      { str = "no\\*meta"; expected = -1; }
      { str = "\\\\*meta"; expected = 2; }
      { str = "escaped\\"; expected = -1; }
      { str = "escaped\\\\"; expected = -1; }
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
      { pattern = "*"; path = "abc"; expected = true; }
      { pattern = "*c"; path = "abc"; expected = true; }
      { pattern = "*/"; path = "a/"; expected = true; }
      { pattern = "a*"; path = "a"; expected = true; }
      { pattern = "a*"; path = "abc"; expected = true; }
      { pattern = "a*"; path = "ab/c"; expected = false; }
      { pattern = "a*/b"; path = "abc/b"; expected = true; }
      { pattern = "a*/b"; path = "a/c/b"; expected = false; }
      { pattern = "a*/c/"; path = "a/b"; expected = false; }
      { pattern = "a*b*c*d*e*"; path = "axbxcxdxe"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxe/f"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxexxx/f"; expected = true; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxe/xxx/f"; expected = false; }
      { pattern = "a*b*c*d*e*/f"; path = "axbxcxdxexxx/fff"; expected = false; }
      { pattern = "a\\*b"; path = "ab"; expected = false; }

      # Globstar / doublestar
      { pattern = "**"; path = ""; expected = true; }
      { pattern = "a/**"; path = "a"; expected = true; }
      { pattern = "a/**/"; path = "a"; expected = true; }
      { pattern = "a/**"; path = "a/"; expected = true; }
      { pattern = "a/**/"; path = "a/"; expected = true; }
      { pattern = "a/**"; path = "a/b"; expected = true; }
      { pattern = "a/**"; path = "a/b/c"; expected = true; }
      { pattern = "**/c"; path = "c"; expected = true; }
      { pattern = "**/c"; path = "b/c"; expected = true; }
      { pattern = "**/c"; path = "a/b/c"; expected = true; }
      { pattern = "**/c"; path = "a/b"; expected = false; }
      { pattern = "**/c"; path = "abcd"; expected = false; }
      { pattern = "**/c"; path = "a/abc"; expected = false; }
      { pattern = "a/**/b"; path = "a/b"; expected = true; }
      { pattern = "a/**/c"; path = "a/b/c"; expected = true; }
      { pattern = "a/**/d"; path = "a/b/c/d"; expected = true; }
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
        pattern = "[a-z]";
        path = "m";
        expected = true;
      }
      {
        pattern = "[a-z]";
        path = "3";
        expected = false;
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
        pattern = "[ef]\\*.c";
        path = "f*.c";
        expected = true;
      }
    ];
  };
}
