{
  description = "Simplify Nix source management using familiar glob patterns";

  inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  inputs.utf8.url = "github:figsoda/utf8";

  outputs = { self, nixpkgs-lib, utf8 }:
    let 
      inherit (builtins)
        fromJSON
        readFile
      ;

      system = "x86_64-linux";

      nodes = (fromJSON (readFile ./dev/flake.lock)).nodes;

      inputFromLock = name:
        let locked = nodes.${name}.locked;
        in fetchTarball {
          url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
          sha256 = locked.narHash;
        };

      nixpkgs = inputFromLock "nixpkgs";

      pkgs = import nixpkgs { inherit system; };

      globset = import self { lib = nixpkgs-lib.lib // { utf8 = utf8.lib; }; };
   
    in {
      lib = globset;

      tests.${system} = import ./internal/tests.nix {
        lib = nixpkgs-lib.lib // { inherit globset; utf8 = utf8.lib; };
      };

      checks.${system}.default = pkgs.runCommand "tests" {
        nativeBuildInputs = [ pkgs.nix-unit ];
      } ''
        export HOME="$(realpath .)"
        nix-unit \
          --eval-store "$HOME" \
          --extra-experimental-features flakes \
          --override-input nixpkgs-lib ${nixpkgs-lib} \
          --override-input utf8 ${utf8} \
          --flake ${self}#tests
        touch $out
      '';
    };
}
