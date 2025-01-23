{ pkgs ? import <nixpkgs> { } }:
let
  lib = pkgs.lib;
  globset = import ./. { inherit lib; };
  fs = lib.fileset;
  testRoot = ./test-data;

  normalizeFileset = fileset:
    builtins.sort builtins.lessThan
    (map (p: lib.removePrefix "${toString testRoot}/" (toString p))
      (lib.fileset.toList fileset));

  runTest = name: result: expected:
    pkgs.writeScript "test-${name}" ''
      #!/usr/bin/env bash
      echo "Testing ${name}..."
      expected='${builtins.toJSON expected}'
      result='${builtins.toJSON result}'
      if [ "$result" = "$expected" ]; then
        echo "PASS: ${name}"
        exit 0
      else
        echo "FAIL: ${name}"
        echo "Expected: $expected"
        echo "Got: $result"
        exit 1
      fi
    '';

  testCases = {
    testGoProject = runTest "globs all Go files" (normalizeFileset
      (globset.lib.globs testRoot [ "go.mod" "go.sum" "**/*.go" ])) [
        "cmd/app/main.go"
        "go.mod"
        "go.sum"
        "pkg/lib/utils.go"
      ];

    testCProject = runTest "globs all C files" (normalizeFileset
      (globset.lib.globs testRoot [ "**/*.c" "**/*.h" "!**/test_*.c" ])) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
      ];

    testDoublestar = runTest "globs all main files"
      (normalizeFileset (globset.lib.glob testRoot "/**/main.*")) [
        "cmd/app/main.go"
        "scripts/main.py"
        "src/main.c"
      ];

    testMidPattern = runTest "** is treated as *"
      (normalizeFileset (globset.lib.glob testRoot "src/**.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];

    testProperDoublestar = runTest "** when used correctly"
      (normalizeFileset (globset.lib.glob testRoot "src/**/*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testPythonFiles = runTest "globs all Python files"
      (normalizeFileset (globset.lib.glob testRoot "**/*.py")) [
        "scripts/main.py"
        "scripts/utils.py"
      ];

    testEscaping = let
      testFileset = globset.lib.globs testRoot [ "src/foo\\*.c" ];
      result = normalizeFileset testFileset;
    in runTest "escaping" result [ "src/foo*.c" ];

    testCharClass = runTest "character class matching"
      (normalizeFileset (globset.lib.glob testRoot "src/[fl]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
      ];

    testCharClassWithEscaping = runTest "character class matching w/ escaping"
      (normalizeFileset (globset.lib.glob testRoot "src/[e-g]oo\\*.c"))
      [ "src/foo*.c" ];

    testCharClassWithEscapingInsideClass =
      runTest "character class matching w/ escaping inside class"
      (normalizeFileset (globset.lib.glob testRoot "src/foo[\\[\\]].o")) [
        "src/foo[.o"
        "src/foo].o"
      ];

    testMultipleCharClassWithEscaping =
      runTest "multiple character class matching w/ escaping"
      (normalizeFileset (globset.lib.glob testRoot "src/[e-g][^n][n-q]\\*.c"))
      [ "src/foo*.c" ];

    testCharRange = runTest "character range matching"
      (normalizeFileset (globset.lib.glob testRoot "**/[a-m]*.py"))
      [ "scripts/main.py" ];

    testNegatedClass = runTest "negated character class"
      (normalizeFileset (globset.lib.glob testRoot "src/[^t]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];

    testNegatedClassMultiple = runTest "negated character class multiple"
      (normalizeFileset (globset.lib.glob testRoot "src/[^lt]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/main.c"
      ];

    testNegatedClassAlt = runTest "negated character class with !"
      (normalizeFileset (globset.lib.glob testRoot "src/[!t]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];

    testCompoundClass = runTest "compound character class patterns"
      (normalizeFileset (globset.lib.glob testRoot "**/*.[ch]")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testClassWithGlobs = runTest "Pass multiple ranges with globs"
      (normalizeFileset
        (globset.lib.globs testRoot [ "**/*[m-o].py" "**/*[r-t].py" ])) [
          "scripts/main.py"
          "scripts/utils.py"
        ];

    testClassWithMixed = runTest "mixed character class with range and literals"
      (normalizeFileset (globset.lib.glob testRoot "**/ma[h-j]n.py"))
      [ "scripts/main.py" ];

    testBasicBrace = runTest "simple brace expansion"
      (normalizeFileset (globset.lib.glob testRoot "src/*.{c,h}")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
      ];

    testEmptyBrace = runTest "empty alternatives in brace"
      (normalizeFileset (globset.lib.glob testRoot "src/{,test/}*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testMultipleBraces = runTest "multiple brace expressions" (normalizeFileset
      (globset.lib.glob testRoot "{src,scripts}/{main,utils}.{c,py}")) [
        "scripts/main.py"
        "scripts/utils.py"
        "src/main.c"
      ];

    testBracesWithEscapedAsterisk = runTest "Braces with escaped asterisk"
      (normalizeFileset (globset.lib.globs testRoot [ "src/{,foo\\*}.c" ]))
      [ "src/foo*.c" ];

    testBracesWithEscapedBraces = runTest "Braces with escaped braces"
      (normalizeFileset (globset.lib.globs testRoot [ "src/foo{\\{,\\}}.o" ])) [
        "src/foo{.o"
        "src/foo}.o"
      ];

    testBracesWithEscapedComma = runTest "Braces with escaped comma"
      (normalizeFileset (globset.lib.globs testRoot [ "src/foo{,\\,}.o" ]))
      [ "src/foo,.o" ];

    testBracesWithEscapedBox = runTest "Braces with escaped box"
      (normalizeFileset (globset.lib.globs testRoot [ "src/foo{\\[,\\]}.o" ])) [
        "src/foo[.o"
        "src/foo].o"
      ];

    testBracesWithAsteriskInside = runTest "Braces with asterisk inside"
      (normalizeFileset (globset.lib.globs testRoot [ "src/{foo*,bar*}.x" ])) [
        "src/bar1.x"
        "src/bar2.x"
        "src/foo1.x"
        "src/foo2.x"
      ];

    testBracesWithBoxInside = runTest "Braces with box inside" (normalizeFileset
      (globset.lib.globs testRoot [ "src/{foo[12],bar[12]}.x" ])) [
        "src/bar1.x"
        "src/bar2.x"
        "src/foo1.x"
        "src/foo2.x"
      ];

    testBracesWithRangeInside = runTest "Braces with range inside"
      (normalizeFileset
        (globset.lib.globs testRoot [ "src/{foo[0-3],bar[0-3]}.x" ])) [
          "src/bar1.x"
          "src/bar2.x"
          "src/foo1.x"
          "src/foo2.x"
        ];

    testBracesWithEmptyResult = runTest "Braces with empty result"
      (normalizeFileset (globset.lib.globs testRoot [ "{foo,bar}/*.c" ])) [ ];

    testMultipleEmptyBraces = runTest "multiple empty alternates"
      (normalizeFileset (globset.lib.glob testRoot "{,src/}{,test/}*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];
  };

  runAllTests =
    pkgs.runCommand "run-all-tests" { nativeBuildInputs = [ pkgs.bash ]; } ''
      ${builtins.concatStringsSep "\n" (builtins.attrValues testCases)}
      mkdir -p $out
      echo "All tests passed!" > $out/result
    '';

in { inherit runAllTests; }
