{
  description = "Simplify Nix source management using familiar glob patterns";

  inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";

  outputs = { self, nixpkgs-lib }:
    let 
      inherit (builtins)
        fromJSON
        readFile
      ;

      systems = [ "x86_64-linux" "aarch64-darwin" ];

      forAllSystems = nixpkgs-lib.lib.genAttrs systems;

      nodes = (fromJSON (readFile ./dev/flake.lock)).nodes;

      inputFromLock = name:
        let locked = nodes.${name}.locked;
        in fetchTarball {
          url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
          sha256 = locked.narHash;
        };

      nixpkgs = inputFromLock "nixpkgs";

      pkgsFor = system: import nixpkgs { inherit system; };

      globset = import self { inherit (nixpkgs-lib) lib; };
    in {
      lib = globset;

      tests = forAllSystems (system: import ./internal/tests.nix {
        lib = nixpkgs-lib.lib // { inherit globset; };
      });

      packages = forAllSystems (system: {
        default = (import ./integration-tests.nix { pkgs = pkgsFor system; });
        integration-tests = (import ./integration-tests.nix { pkgs = pkgsFor system; });
      });

      checks = forAllSystems (system: {
        default =
          (pkgsFor system).runCommand "tests" { nativeBuildInputs = [ (pkgsFor system).nix-unit ]; } ''
            export HOME="$(realpath .)"
            nix-unit \
              --eval-store "$HOME" \
              --extra-experimental-features flakes \
              --override-input nixpkgs-lib ${nixpkgs-lib} \
              --flake ${self}#tests
            touch $out
          '';

        integration-tests = (import ./integration-tests.nix { pkgs = pkgsFor system; });
      });
    };
  }
