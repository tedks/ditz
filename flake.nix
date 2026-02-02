{
  description = "ditz - distributed issue tracker (OCaml rewrite)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, opam-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        opam = opam-nix.lib.${system};

        # Build the project from the ocaml subdirectory
        # API: (buildDuneProject { } "package-name" ./path { ocaml = "version"; }).package-name
        scope = opam.buildDuneProject { } "ditz" ./ocaml { ocaml = "5.1.1"; };

        # The main package
        ditz = scope.ditz;

      in
      {
        packages = {
          default = ditz;
          inherit ditz;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ ditz ];

          buildInputs = with pkgs; [
            # OCaml dev tools
            ocamlPackages.ocamlformat
            ocamlPackages.ocaml-lsp

            # For the original Ruby ditz (comparison/compat testing)
            ruby

            # Useful for development
            git
          ];

          shellHook = ''
            echo "ditz development environment (opam-nix)"
            echo ""
            echo "Build:"
            echo "  dune build"
            echo ""
            echo "Run:"
            echo "  dune exec ditz -- <command>"
            echo ""
            echo "Or use the built package:"
            echo "  nix run .#ditz -- <command>"
            echo ""
            echo "All OCaml dependencies are pre-built - no opam bootstrap needed!"
          '';
        };

        # Allow running directly: nix run github:tedks/ditz -- list
        apps.default = {
          type = "app";
          program = "${ditz}/bin/ditz";
        };
      });
}
