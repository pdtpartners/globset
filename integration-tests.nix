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
    testGoProject = runTest "globs all Go files"
      (normalizeFileset (globset.globs testRoot [ "go.*" "**/*.go" ])) [
        "cmd/app/main.go"
        "go.mod"
        "go.sum"
        "pkg/lib/utils.go"
      ];

    testCProject = runTest "globs all C files that aren't tests"
      (normalizeFileset
        (globset.globs testRoot [ "**/*.c" "**/*.h" "!**/test_*.c" ])) [
          "src/foo*.c"
          "src/foobar.c"
          "src/lib.c"
          "src/lib.h"
          "src/main.c"
        ];

    testDoublestar = runTest "globs all main files"
      (normalizeFileset (globset.glob testRoot "/**/main.*")) [
        "cmd/app/main.go"
        "scripts/main.py"
        "src/main.c"
      ];

    testMidPattern = runTest "** is treated as *"
      (normalizeFileset (globset.glob testRoot "src/**.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];

    testProperDoublestar = runTest "** when used correctly"
      (normalizeFileset (globset.glob testRoot "src/**/*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testPythonFiles = runTest "globs all Python files"
      (normalizeFileset (globset.glob testRoot "**/*.py")) [
        "scripts/main.py"
        "scripts/utils.py"
      ];

    testEscaping = let
      testFileset = globset.globs testRoot [ "src/foo\\*.c" ];
      result = normalizeFileset testFileset;
    in runTest "escaping" result [ "src/foo*.c" ];

    testGlobsOrdering = runTest "globs ordering" (normalizeFileset
      (globset.globs testRoot [ "**/*.c" "!**/test_*.c" "src/test/**/*.c" ])) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testEmptyGlobs =
      runTest "empty globs list" (normalizeFileset (globset.globs testRoot [ ]))
      [ ];

    testEmptyGlobs2 = runTest "empty globs list 2"
      (normalizeFileset (globset.globs testRoot [ "foo/**/*.c" ])) [ ];

    testEmptyGlobs3 = runTest "empty globs list 3" (normalizeFileset
      (globset.globs testRoot [ "**/foo/*.c" "**/test/**/*.x" ])) [ ];

    testGetAllNixFiles = runTest "globs all nix files" (normalizeFileset
      (globset.globs testRoot [
        "**/*.nix"
        "*.nix"
        "!home-manager/generated.nix"
        "home-manager/users/teto/default.nix"
      ])) [
        "home-manager/users/root/default.nix"
        "home-manager/users/teto/default.nix"
        "home-manager/users/teto/programs/neovim.nix"
        "home-manager/users/teto/programs/waybar.nix"
        "home-manager/users/teto/programs/zsh.nix"
        "home-manager/users/teto/services/blueman-applet.nix"
        "home-manager/users/teto/services/mpd.nix"
        "home-manager/users/teto/services/swayidle.nix"
        "home-manager/users/teto/sway.nix"
        "home-manager/users/teto/swaync.nix"
      ];
  };

  runAllTests =
    pkgs.runCommand "run-all-tests" { nativeBuildInputs = [ pkgs.bash ]; } ''
      ${builtins.concatStringsSep "\n" (builtins.attrValues testCases)}
      mkdir -p $out
      echo "All tests passed!" > $out/result
    '';

in { inherit runAllTests; }
