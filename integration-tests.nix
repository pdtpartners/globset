{ pkgs, utf8 ? pkgs.lib.utf8 }:
let
  lib = pkgs.lib // { inherit utf8; };
  globset = import ./. { inherit lib; };
  testRoot = ./test-data;

  sanitizePath = p: builtins.unsafeDiscardStringContext (toString p);

  normalizeFileset = fileset:
    builtins.sort builtins.lessThan
    (map (p: lib.removePrefix "${toString testRoot}/" (sanitizePath p))
      (lib.fileset.toList fileset));

  runTest = name: result: expected:
    pkgs.stdenv.mkDerivation {
      name = "test-${lib.strings.sanitizeDerivationName name}";
      passAsFile = [ "expectedJson" "resultJson" ];
      expectedJson = builtins.toJSON expected;
      resultJson = builtins.toJSON result;

      builder = pkgs.writeShellScript "builder.sh" ''
        source $stdenv/setup
        # Create output directory
        mkdir -p $out
        echo "Testing ${name}..."
        # Compare the JSON files
        if diff -u "$expectedJsonPath" "$resultJsonPath" > $out/diff; then
          echo "PASS: ${name}" | tee $out/result
          exit 0
        else
          echo "FAIL: ${name}" | tee $out/result
          echo "Expected:" | tee -a $out/result
          cat "$expectedJsonPath" | tee -a $out/result
          echo "Got:" | tee -a $out/result
          cat "$resultJsonPath" | tee -a $out/result
          exit 1
        fi
      '';

      dontUnpack = true;
      nativeBuildInputs = [ pkgs.diffutils ];
    };

  testCases = {
    testGoProject = runTest "globs all Go files"
      (normalizeFileset (globset.globs testRoot [ "go.*" "**/*.go" ])) [
        "cmd/app/main.go"
        "go.mod"
        "go.sum"
        "pkg/lib/utils.go"
      ];

    testUTFChars = runTest "globs files with an utf8 char match constraint"
      (normalizeFileset (globset.globs testRoot [ "gø.*" "**/*.gø" ])) [
        "foo*.gø"
        "foo.gø"
        "gø.foo"
      ];
    
    testUTFCharsWithNegation = runTest "globs files with an utf8 char match constraint with negation"
      (normalizeFileset (globset.globs testRoot [ "gø.*" "**/*.gø" "!*.foo" ])) [
        "foo*.gø"
        "foo.gø"
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

    testEscapingWithUTF8 = let
      testFileset = globset.globs testRoot [ "foo\\*.gø" ];
      result = normalizeFileset testFileset;
    in runTest "escaping with utf-8" result [ "foo*.gø" ];

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

    testCharClass = runTest "character class matching"
      (normalizeFileset (globset.glob testRoot "src/[fl]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
      ];
    
    testCharClassWithUTF8 = runTest "character class matching w/ utf-8"
      (normalizeFileset (globset.glob testRoot "*.g[ø¬˚]")) [
        "foo*.gø"
        "foo.gø"
      ];

    testCharClassWithEscaping = runTest "character class matching w/ escaping"
      (normalizeFileset (globset.glob testRoot "src/[e-g]oo\\*.c"))
      [ "src/foo*.c" ];
    
    testCharClassWithEscapingAndUTF8 = runTest "character class matching w/ escaping and utf8"
      (normalizeFileset (globset.glob testRoot "[e-g]oo\\*.[f-h][ø¬˚]"))
      [ "foo*.gø" ];

    testCharClassWithEscaping2 = runTest "character class matching w/ escaping 2"
      (normalizeFileset (globset.glob testRoot "src/[e-g]oo\\-.[oc]"))
      [ "src/foo-.o" ];

    testCharClassWithEscapingInsideClass =
      runTest "character class matching w/ escaping inside class"
      (normalizeFileset (globset.glob testRoot "src/[e-g]oo[\\[\\-\\]\\*].[oc]")) [
        "src/foo*.c"
        "src/foo-.o"
        "src/foo[.o"
        "src/foo].o"
      ];
    
    testCharClassWithEscapingInsideClassAndUTF8 =
      runTest "character class matching w/ escaping inside class and utf8"
      (normalizeFileset (globset.glob testRoot "[e-g]oo[\\*].gø")) [
        "foo*.gø"
      ];

    testMultipleCharClassWithEscaping =
      runTest "multiple character class matching w/ escaping"
      (normalizeFileset (globset.glob testRoot "src/[e-g][^n][n-q]\\*.c"))
      [ "src/foo*.c" ];

    testCharRange = runTest "character range matching"
      (normalizeFileset (globset.glob testRoot "**/[a-m]*.py"))
      [ "scripts/main.py" ];
    
    testCharRangeWithUTF8 = runTest "character range matching with utf8"
      (normalizeFileset (globset.glob testRoot "**/*.g[ø-ÿ]"))
      [ "foo*.gø" "foo.gø" ];

    testNegatedClass = runTest "negated character class"
      (normalizeFileset (globset.glob testRoot "src/[^t]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];
    
    testNegatedClassWithUTF8 = runTest "negated character class w/ utf8"
      (normalizeFileset (globset.glob testRoot "g[^˜∂∆].foo")) [
        "gø.foo"
      ];
    
    testAlternateNegatedClassWithUTF8 = runTest "negated character class w/ utf8"
      (normalizeFileset (globset.glob testRoot "g[!˜∂∆].foo")) [
        "gø.foo"
      ];

    testNegatedClassMultiple = runTest "negated character class multiple"
      (normalizeFileset (globset.glob testRoot "src/[^lt]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/main.c"
      ];

    testNegatedClassAlt = runTest "negated character class with !"
      (normalizeFileset (globset.glob testRoot "src/[!t]*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
      ];

    testCompoundClass = runTest "compound character class patterns"
      (normalizeFileset (globset.glob testRoot "**/*.[ch]")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testClassWithGlobs = runTest "Pass multiple ranges with globs"
      (normalizeFileset
        (globset.globs testRoot [ "**/*[m-o].py" "**/*[r-t].py" ])) [
          "scripts/main.py"
          "scripts/utils.py"
        ];

    testClassWithMixed = runTest "mixed character class with range and literals"
      (normalizeFileset (globset.glob testRoot "**/ma[h-j]n.py"))
      [ "scripts/main.py" ];

    testEmptyCharClass = runTest "empty char class"
      (normalizeFileset (globset.glob testRoot "src/[]*.c"))
      [ ];
    
    testBasicBrace = runTest "simple brace expansion"
      (normalizeFileset (globset.glob testRoot "src/*.{c,h,x}")) [
        "src/bar1.x"
        "src/bar2.x"
        "src/foo*.c"
        "src/foo1.x"
        "src/foo2.x"
        "src/foobar.c"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
      ];
    
    testBasicBraceWithUTF8 = runTest "simple brace expansion w/ utf8"
      (normalizeFileset (globset.glob testRoot "g{o,ø}.*")) [
        "go.mod"
        "go.sum"
        "gø.foo"
      ];

    testEmptyBrace = runTest "empty alternatives in brace"
      (normalizeFileset (globset.glob testRoot "src/{,test/}*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];
    
    testEmptyBraceWithUTF8 = runTest "empty alternatives in brace w/ utf-8"
      (normalizeFileset (globset.glob testRoot "foo{,\\*}.gø")) [
        "foo*.gø"
        "foo.gø"
      ];

    testMultipleBraces = runTest "multiple brace expressions" (normalizeFileset
      (globset.glob testRoot "{src,scripts}/{main,utils}.{c,py}")) [
        "scripts/main.py"
        "scripts/utils.py"
        "src/main.c"
      ];
    
    testMultipleBracesWithUTF8 = runTest "multiple brace expressions w/ utf-8" (normalizeFileset
      (globset.glob testRoot "{foo,foo*}.{go,gø}")) [
        "foo*.gø"
        "foo.gø"
      ];

    testBracesWithEscapedAsterisk = runTest "Braces with escaped asterisk"
      (normalizeFileset (globset.globs testRoot [ "src/{,foo\\*}.c" ]))
      [ "src/foo*.c" ];

    testBracesWithEscapedBraces = runTest "Braces with escaped braces"
      (normalizeFileset (globset.globs testRoot [ "src/foo{\\{,\\}}.o" ])) [
        "src/foo{.o"
        "src/foo}.o"
      ];

    testBracesWithEscapedComma = runTest "Braces with escaped comma"
      (normalizeFileset (globset.globs testRoot [ "src/foo{,\\,}.o" ]))
      [ "src/foo,.o" ];

    testBracesWithEscapedBox = runTest "Braces with escaped box"
      (normalizeFileset (globset.globs testRoot [ "src/foo{\\[,\\]}.o" ])) [
        "src/foo[.o"
        "src/foo].o"
      ];

    testBracesWithAsteriskInside = runTest "Braces with asterisk inside"
      (normalizeFileset (globset.globs testRoot [ "src/{foo*,bar*}.x" ])) [
        "src/bar1.x"
        "src/bar2.x"
        "src/foo1.x"
        "src/foo2.x"
      ];

    testBracesWithBoxInside = runTest "Braces with box inside" (normalizeFileset
      (globset.globs testRoot [ "src/{foo[12],bar[12]}.x" ])) [
        "src/bar1.x"
        "src/bar2.x"
        "src/foo1.x"
        "src/foo2.x"
      ];

    testBracesWithRangeInside = runTest "Braces with range inside"
      (normalizeFileset
        (globset.globs testRoot [ "src/{foo[0-3],bar[0-3]}.x" ])) [
          "src/bar1.x"
          "src/bar2.x"
          "src/foo1.x"
          "src/foo2.x"
        ];
    
    testBracesWithRangeInsideAndUTF8 = runTest "Braces with range inside w/ utf8"
      (normalizeFileset
        (globset.globs testRoot [ "foo.{g[ø-ÿ]}" ])) [
          "foo.gø"
        ];

    testBracesWithEmptyResult = runTest "Braces with empty result"
      (normalizeFileset (globset.globs testRoot [ "{foo,bar}/*.c" ])) [ ];

    testMultipleEmptyBraces = runTest "multiple empty alternates"
      (normalizeFileset (globset.glob testRoot "{,src/}{,test/}*.c")) [
        "src/foo*.c"
        "src/foobar.c"
        "src/lib.c"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testComplexPattern = runTest "complex pattern combining multiple features"
      (normalizeFileset (globset.glob testRoot "{cmd,home-manager,pkg,scripts,src}/**/*.{[ch],[xo],go,nix}")) [
        "cmd/app/main.go"
        "home-manager/generated.nix"
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
        "pkg/lib/utils.go"
        "src/bar1.x"
        "src/bar2.x"
        "src/foo*.c"
        "src/foo,.o"
        "src/foo-.o"
        "src/foo1.x"
        "src/foo2.x"
        "src/foo[.o"
        "src/foo].o"
        "src/foobar.c"
        "src/foo{.o"
        "src/foo}.o"
        "src/lib.c"
        "src/lib.h"
        "src/main.c"
        "src/test/test_main.c"
      ];

    testComplexPattern2 = runTest "complex pattern combining multiple features 2"
      (normalizeFileset (globset.globs testRoot [
        "{cmd,home-manager,pkg,scripts,src}/**/*.{[ch],[xo],go,nix}"
        "!src/**"
      ])) [
        "cmd/app/main.go"
        "home-manager/generated.nix"
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
        "pkg/lib/utils.go"
      ];

    testComplexPattern3 = runTest "complex pattern combining multiple features 3"
      (normalizeFileset (globset.globs testRoot [
        "{cmd,home-manager,pkg,scripts,src}/**/*.{[ch],[xo],go,nix}"
        "!{src,home-manager}/**"
      ])) [
        "cmd/app/main.go"
        "pkg/lib/utils.go"
      ];

    testComplexPattern4 = runTest "complex pattern combining multiple features 4"
      (normalizeFileset (globset.globs testRoot [
        "{cmd,home-manager,pkg,scripts,src}/**/*.{[ch],[xo],go,nix}"
        "!{src,home-manager,cmd}/**"
      ])) [
        "pkg/lib/utils.go"
      ];
    
    testComplexPattern5 = runTest "complex pattern combining multiple features 5"
      (normalizeFileset (globset.globs testRoot [
        "**/*.{[c-x],go,nix}"
        "!{src,home-manager,cmd}/**"
      ])) [
        "pkg/lib/utils.go"
      ];
  };

  runAllTests = pkgs.linkFarm "run-all-tests"
    (map (drv: { name = drv.name; path = drv; }) (builtins.attrValues testCases));

in runAllTests
