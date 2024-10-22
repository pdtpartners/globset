<div align="center">

# globset

[![ci][ci-badge]][ci]

globset is a [Nix][nix] library that enables familiar globbing patterns for
[filesets][fileset], providing a simple interface for source filtering. The core
is a port of bmatcuk's excellent [doublestar] Golang library for globs.

![globs](images/globset.svg)

[Key features](#key-features) •
[Getting started](#getting-started) •
[Patterns](#patterns) •
[Usage](#usage) •
[Contributing](CONTRIBUTING.md)

</div>

## Key features

- Advanced Globbing: Support for single `*` and double `**` wildcards, along
  with pattern exclusions using `!`.
- Maximum Laziness: Files never added to store unless explicitly requested with
  `lib.fileset.toSource`.
- Composability: Composes with any other library that returns FileSets.

## Getting started

To use `globset` in your Nix project, either add it as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    globset = {
      url = "github:pdtpartners/globset";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, globset }:
    let
      system = "x86_64-linux"; 
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.foobar = pkgs.buildGoModule {
        /* ... */
        src = lib.fileset.toSource {
          root = ./.;
          fileset = globset.lib.globs ./. [ "go.mod" "go.sum" "**/*.go" ];
        };
      };
    };
}

```

or use `fetchTarball`:

```nix
{ pkgs ? import <nixpkgs> {}
, globset ? import (builtins.fetchTarball "https://github.com/pdtpartners/globset/archive/main.tar.gz");
}:

pkgs.buildGoModule {
  /* ... */
  src = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = globset.lib.globs ./. [ "go.mod" "go.sum" "**/*.go" ];
  };
}
```

## Patterns

`globset` supports the following special terms in the patterns:

Special Terms | Meaning
------------- | -------
`*`           | matches any sequence of non-path-separators
`/**/`        | matches zero or more directories

Any character with a special meaning can be escaped with a backslash (`\`).

A doublestar (`**`) should appear surrounded by path separators such as `/**/`.
A mid-pattern doublestar (`**`) behaves like bash's globstar option, it is
treated like a single star. For example, `path/to/**.txt` will return the same
results as `path/to/*.txt`. Instead, you are likely looking for
`path/to/**/*.txt`.

## Usage

### globs

```nix
# Type:
#   globs :: Path -> [ String ] -> FileSet
#
# Example:
#   # Collect files matching patterns in the `src` directory
#   globs ./src [
#     "**/*.c"          # Include all C source files
#     "**/*.h"          # Include all header files
#     "!**/test_*"      # Exclude test files
#   ]
globs = root: patterns:
```

The file set containing all files that match any of the given glob patterns,
starting from the specified root directory.

This function processes a list of glob patterns, which can include negative
patterns starting with `!` to exclude files from the resulting set. Patterns
are applied in order, with exclusions overriding previous inclusions. Negative
patterns must come after the positive patterns they are meant to exclude.

This is similar to the Unix shell globbing mechanism but extended to support
negative patterns for exclusions.

### glob

```nix
# Type:
#   glob :: Path -> String -> FileSet
#
# Example:
#   # Collect all Python files in the `scripts` directory
#   glob ./scripts "**/*.py"
#
# See also:
#   - [Pattern matching](https://en.wikipedia.org/wiki/Glob_(programming)).
glob = root: pattern:
````

The file set containing all files that match the given glob pattern, starting
from the specified root directory.

This function expands the glob pattern relative to the root directory and
returns a file set of the matching files.

### match

```nix
# Type:
#   match :: String -> String -> Bool
#
# Examples:
#   match "a*/b" "abc/b"  # Returns true
#   match "a*/b" "a/c/b"  # Returns false
#   match "**/c" "a/b/c"  # Returns true
#   match "**/c" "a/b"    # Returns false
#   match "a\\*b" "ab"    # Returns false
#   match "a\\*b" "a*b"   # Returns true
match = pattern: name:
```

Determines whether a given file name matches a glob pattern.

This function supports single `*` wildcards matching any sequence of characters
except directory separators, double `**` wildcards matching any sequence of
characters including directory separators, and escaping of meta characters
using backslashes.

This is useful for testing patterns against file names or paths.

## Contributing

Pull requests are welcome for any changes. Consider opening an issue to discuss
larger changes first to get feedback on the idea.

## License

The source code developed for globset is licensed under MIT License.

[ci]: https://github.com/pdtpartners/globset/actions?query=workflow%3ACI
[ci-badge]: https://github.com/pdtpartners/globset/actions/workflows/ci.yml/badge.svg
[doublestar]: https://github.com/bmatcuk/doublestar
[fileset]: https://www.tweag.io/blog/2023-11-28-file-sets/
[nix]: https://zero-to-nix.com/concepts/nix
