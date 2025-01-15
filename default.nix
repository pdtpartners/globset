{ lib }:
let
  inherit (import ./internal/src/glob.nix { inherit lib; }) glob globs;
  inherit (import ./internal/src/match.nix { inherit lib; }) match;
in { lib = { inherit glob globs match; }; }
