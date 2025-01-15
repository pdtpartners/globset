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

  runAllTests =
    pkgs.runCommand "run-all-tests" { nativeBuildInputs = [ pkgs.bash ]; } ''
      ${testGoProject}
      ${testCProject}
      ${testDoublestar}
      ${testMidPattern}
      ${testProperDoublestar}
      ${testPythonFiles}
      ${testEscaping}
      mkdir -p $out
      echo "All tests passed!" > $out/result
    '';

in { inherit runAllTests testGoProject testCProject; }
