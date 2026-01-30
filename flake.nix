{
  description = "ditz - distributed issue tracker (OCaml rewrite)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # OCaml toolchain
            opam
            ocaml
            dune_3
            ocamlformat

            # System deps for opam packages
            pkg-config
            gmp
            libffi

            # For the original Ruby ditz (if we want to compare)
            ruby
          ];

          shellHook = ''
            echo "ditz development environment"
            echo ""
            echo "First time setup:"
            echo "  opam init --bare (if not done globally)"
            echo "  opam switch create . ocaml-base-compiler.5.1.1 --deps-only"
            echo "  eval \$(opam env)"
            echo "  opam install . --deps-only"
            echo ""
            echo "Build:"
            echo "  dune build"
            echo ""
            echo "Run:"
            echo "  dune exec ditz -- <command>"
          '';
        };
      });
}
