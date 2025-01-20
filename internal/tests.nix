{ lib }:

let
  inherit (builtins) listToAttrs genList length elemAt;

  internal = import ./. { inherit lib; };

  mkSuite = { testNameFn, valueFn, tests }:
    listToAttrs (genList (i:
      let
        testCase = elemAt tests i;
        testName = testNameFn testCase;
      in {
        name = "test (${testName})";
        value = {
          expr = valueFn testCase;
          expected = testCase.expected;
        };
      }) (length tests));

in {
  firstUnescapedMeta = mkSuite {
    testNameFn = testCase: ''firstUnescapedMeta "${testCase.str}"'';
    valueFn = testCase: internal.firstUnescapedMeta testCase.str;
    tests = [
      {
        str = "";
        expected = -1;
      }
      {
        str = "*abc";
        expected = 0;
      }
      {
        str = "\\*a*";
        expected = 3;
      }
      {
        str = "abc\\*def";
        expected = -1;
      }
      {
        str = "ab\\*cd*ef";
        expected = 6;
      }
      {
        str = "no\\*meta";
        expected = -1;
      }
      {
        str = "\\\\*meta";
        expected = 2;
      }
      {
        str = "escaped\\";
        expected = -1;
      }
      {
        str = "escaped\\\\";
        expected = -1;
      }
    ];
  };

  match = mkSuite {
    testNameFn = testCase: ''match "${testCase.pattern}" "${testCase.path}"'';
    valueFn = testCase: internal.match testCase.pattern testCase.path;
    tests = [
      # Single glob
      {
        pattern = "*";
        path = "";
        expected = true;
      }
      {
        pattern = "*";
        path = "/";
        expected = false;
      }
      {
        pattern = "/*";
        path = "/";
        expected = true;
      }
      {
        pattern = "/*";
        path = "/debug/";
        expected = false;
      }
      {
        pattern = "/*";
        path = "//";
        expected = false;
      }
      {
        pattern = "abc";
        path = "abc";
        expected = true;
      }
      {
        pattern = "*";
        path = "abc";
        expected = true;
      }
      {
        pattern = "*c";
        path = "abc";
        expected = true;
      }
      {
        pattern = "*/";
        path = "a/";
        expected = true;
      }
      {
        pattern = "a*";
        path = "a";
        expected = true;
      }
      {
        pattern = "a*";
        path = "abc";
        expected = true;
      }
      {
        pattern = "a*";
        path = "ab/c";
        expected = false;
      }
      {
        pattern = "a*/b";
        path = "abc/b";
        expected = true;
      }
      {
        pattern = "a*/b";
        path = "a/c/b";
        expected = false;
      }
      {
        pattern = "a*/c/";
        path = "a/b";
        expected = false;
      }
      {
        pattern = "a*b*c*d*e*";
        path = "axbxcxdxe";
        expected = true;
      }
      {
        pattern = "a*b*c*d*e*/f";
        path = "axbxcxdxe/f";
        expected = true;
      }
      {
        pattern = "a*b*c*d*e*/f";
        path = "axbxcxdxexxx/f";
        expected = true;
      }
      {
        pattern = "a*b*c*d*e*/f";
        path = "axbxcxdxe/xxx/f";
        expected = false;
      }
      {
        pattern = "a*b*c*d*e*/f";
        path = "axbxcxdxexxx/fff";
        expected = false;
      }
      {
        pattern = "a\\*b";
        path = "ab";
        expected = false;
      }

      # Globstar / doublestar
      {
        pattern = "**";
        path = "";
        expected = true;
      }
      {
        pattern = "a/**";
        path = "a";
        expected = true;
      }
      {
        pattern = "a/**/";
        path = "a";
        expected = true;
      }
      {
        pattern = "a/**";
        path = "a/";
        expected = true;
      }
      {
        pattern = "a/**/";
        path = "a/";
        expected = true;
      }
      {
        pattern = "a/**";
        path = "a/b";
        expected = true;
      }
      {
        pattern = "a/**";
        path = "a/b/c";
        expected = true;
      }
      {
        pattern = "**/c";
        path = "c";
        expected = true;
      }
      {
        pattern = "**/c";
        path = "b/c";
        expected = true;
      }
      {
        pattern = "**/c";
        path = "a/b/c";
        expected = true;
      }
      {
        pattern = "**/c";
        path = "a/b";
        expected = false;
      }
      {
        pattern = "**/c";
        path = "abcd";
        expected = false;
      }
      {
        pattern = "**/c";
        path = "a/abc";
        expected = false;
      }
      {
        pattern = "a/**/b";
        path = "a/b";
        expected = true;
      }
      {
        pattern = "a/**/c";
        path = "a/b/c";
        expected = true;
      }
      {
        pattern = "a/**/d";
        path = "a/b/c/d";
        expected = true;
      }
      {
        pattern = "a/\\**";
        path = "a/b/c";
        expected = false;
      }

      # Character class
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
        pattern = "[^]";
        path = "foo.c";
        expected = true;
      }
    ];
  };

  lastIndexSlash = mkSuite {
    testNameFn = testCase: ''lastIndexSlash "${testCase.input}"'';
    valueFn = testCase: internal.lastIndexSlash testCase.input;

    tests = [
      {
        input = "";
        expected = -1;
      }
      {
        input = "foo";
        expected = -1;
      }
      {
        input = "foo/";
        expected = 3;
      }
      {
        input = "foo/bar";
        expected = 3;
      }
      {
        input = "foo\\/bar";
        expected = -1;
      }
      {
        input = "/foo/bar";
        expected = 4;
      }
    ];
  };

  findNextSeparator = mkSuite {
    testNameFn = testCase:
      ''findNextSeparator "${testCase.input}" ${toString testCase.startIdx}'';
    valueFn = testCase:
      internal.findNextSeparator testCase.input testCase.startIdx;
    tests = [
      {
        input = "";
        startIdx = 0;
        expected = -1;
      }
      {
        input = "foo";
        startIdx = 0;
        expected = -1;
      }
      {
        input = "foo/bar";
        startIdx = 0;
        expected = 3;
      }
      {
        input = "foo/bar";
        startIdx = 4;
        expected = -1;
      }
      {
        input = "/foo/bar";
        startIdx = 0;
        expected = 0;
      }
    ];
  };

  unescapeMeta = mkSuite {
    testNameFn = testCase: ''unescapeMeta "${testCase.input}"'';
    valueFn = testCase: internal.unescapeMeta testCase.input;
    tests = [
      {
        input = "";
        expected = "";
      }
      {
        input = "\\*";
        expected = "*";
      }
      {
        input = "foo\\*bar";
        expected = "foo*bar";
      }
      {
        input = "\\*\\*";
        expected = "**";
      }
    ];
  };

  isZeroLengthPattern = mkSuite {
    testNameFn = testCase: ''isZeroLengthPattern "${testCase.input}"'';
    valueFn = testCase: internal.isZeroLengthPattern testCase.input;
    tests = [
      {
        input = "";
        expected = true;
      }
      {
        input = "*";
        expected = true;
      }
      {
        input = "**";
        expected = true;
      }
      {
        input = "/**";
        expected = true;
      }
      {
        input = "**/";
        expected = true;
      }
      {
        input = "/**/";
        expected = true;
      }
      {
        input = "foo";
        expected = false;
      }
      {
        input = "foo*";
        expected = false;
      }
    ];
  };

  inCharRange = mkSuite {
    testNameFn = testCase:
      ''inCharRange "${testCase.start}" "${testCase.end}" "${testCase.char}"'';
    valueFn = testCase:
      internal.inCharRange testCase.start testCase.end testCase.char;
    tests = [
      {
        start = "a";
        end = "z";
        char = "m";
        expected = true;
      }
      {
        start = "0";
        end = "9";
        char = "5";
        expected = true;
      }
      {
        start = "a";
        end = "f";
        char = "g";
        expected = false;
      }
      {
        start = "A";
        end = "Z";
        char = "a";
        expected = false;
      }
    ];
  };

  parseCharClass = mkSuite {
    testNameFn = testCase:
      ''parseCharClass "${testCase.input}" ${toString testCase.startIdx}'';
    valueFn = testCase:
      internal.parseCharClass testCase.input testCase.startIdx;
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
        input = "foo[^a-z]bar";
        startIdx = 3;
        expected = {
          content = "^a-z";
          endIdx = 8;
          isNegated = true;
        };
      }
    ];
  };

  matchesCharClass = mkSuite {
    testNameFn = testCase:
      ''matchesCharClass "${testCase.class}" "${testCase.char}"'';
    valueFn = testCase: internal.matchesCharClass testCase.class testCase.char;
    tests = [
      {
        class = "abc";
        char = "b";
        expected = true;
      }
      {
        class = "abc";
        char = "d";
        expected = false;
      }
      {
        class = "a-z";
        char = "m";
        expected = true;
      }
      {
        class = "a-z";
        char = "A";
        expected = false;
      }
      {
        class = "0-9";
        char = "5";
        expected = true;
      }
      {
        class = "0-9";
        char = "a";
        expected = false;
      }
      {
        class = "^abc";
        char = "d";
        expected = true;
      }
      {
        class = "^abc";
        char = "b";
        expected = false;
      }
      {
        class = "^a-z";
        char = "5";
        expected = true;
      }
      {
        class = "^a-z";
        char = "m";
        expected = false;
      }
      {
        class = "!aeiou";
        char = "x";
        expected = true;
      }
      {
        class = "!aeiou";
        char = "e";
        expected = false;
      }
      {
        class = "!0-9";
        char = "a";
        expected = true;
      }
      {
        class = "!0-9";
        char = "5";
        expected = false;
      }
      {
        class = "";
        char = "x";
        expected = false;
      }
      {
        class = "a";
        char = "a";
        expected = true;
      }
      {
        class = "abc-";
        char = "-";
        expected = true;
      }
      {
        class = "-abc";
        char = "-";
        expected = true;
      }
    ];
  };
}
