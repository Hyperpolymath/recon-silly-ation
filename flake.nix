{
  description = "recon-silly-ation: Documentation Reconciliation System (RSR-compliant)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "wasm32-unknown-unknown" ];
        };

      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Deno runtime
            deno

            # Rust for WASM modules
            rustToolchain
            cargo
            rustfmt
            clippy

            # Haskell for validator
            ghc
            cabal-install

            # Build tools
            just
            podman
            podman-compose

            # Development tools
            git
            curl
            jq

            # Optional: ArangoDB client
            # arangodb  # Uncomment if available in nixpkgs
          ];

          shellHook = ''
            echo "🦕 recon-silly-ation development environment"
            echo ""
            echo "Available tools:"
            echo "  deno --version"
            echo "  cargo --version"
            echo "  ghc --version"
            echo "  just --list"
            echo ""
            echo "Quick start:"
            echo "  just build        # Build WASM + cache deps"
            echo "  just test         # Run tests"
            echo "  just scan /repo   # Scan a repository"
            echo ""
            echo "Documentation: README.adoc"
            echo "RSR Compliance: docs/RSR-COMPLIANCE-AUDIT.adoc"
            echo ""

            # Set up Deno cache directory
            export DENO_DIR="$PWD/.deno_cache"

            # Add local bin to PATH
            export PATH="$PWD/bin:$PATH"
          '';
        };

        # Build the project
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "recon-silly-ation";
          version = "0.2.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            deno
            rustToolchain
            cargo
            just
          ];

          buildPhase = ''
            # Build WASM modules
            cd wasm-modules
            cargo build --release --target wasm32-unknown-unknown
            cd ..

            # Cache Deno dependencies
            deno cache src/main.ts

            # Compile to AOT binary
            deno compile \
              --allow-all \
              --unstable-ffi \
              --output=recon-silly-ation \
              src/main.ts
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp recon-silly-ation $out/bin/

            # Copy WASM modules
            mkdir -p $out/share/recon-silly-ation/wasm
            cp wasm-modules/target/wasm32-unknown-unknown/release/recon_wasm.wasm \
               $out/share/recon-silly-ation/wasm/hasher.wasm

            # Copy documentation
            mkdir -p $out/share/doc/recon-silly-ation
            cp README.adoc CONTRIBUTING.adoc LICENSE.txt SECURITY.md $out/share/doc/recon-silly-ation/
            cp -r docs $out/share/doc/recon-silly-ation/
          '';

          meta = with pkgs.lib; {
            description = "Documentation Reconciliation System with WASM acceleration";
            homepage = "https://github.com/Hyperpolymath/recon-silly-ation";
            license = [ licenses.mit ]; # Dual MIT + Palimpsest v0.8
            maintainers = [ "Hyperpolymath" ];
            platforms = platforms.unix;
          };
        };

        # App for running the compiled binary
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/recon-silly-ation";
        };

        # Checks (tests)
        checks = {
          build = self.packages.${system}.default;

          format-check = pkgs.runCommand "format-check" {} ''
            ${pkgs.deno}/bin/deno fmt --check ${./.}/src || exit 1
            touch $out
          '';

          lint = pkgs.runCommand "lint" {} ''
            ${pkgs.deno}/bin/deno lint ${./.}/src || exit 1
            touch $out
          '';
        };

        # Formatter
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
