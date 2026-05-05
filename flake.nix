{
  description = "Nix-Book: The Nix Package Manager";

  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, utils }:
    let
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin"];
      localOverlay = import ./nix/overlay.nix;
      forSystem = system: rec {
        legacyPackages = import nixpkgs {
          inherit system;
          overlays = [localOverlay];
        };
        packages = utils.lib.flattenTree {
          inherit (legacyPackages) devShell nix-book;
        };
        defaultPackage = packages.nix-book;
        apps.nix-book = utils.lib.mkApp {drv = packages.nix-book;};
        hydraJobs = {inherit (legacyPackages) nix-book;};
        checks = {
          inherit (legacyPackages) nix-book;

          # Link checking (requires network access, run manually or in CI)
          # Enable manually with: nix build .#checks.x86_64-linux.link-check
          # link-check = legacyPackages.callPackage ./nix/checks/link-check.nix {
          #   book = legacyPackages.nix-book;
          # };

          # Markdown linting
          markdown-lint = legacyPackages.callPackage ./nix/checks/markdown-lint.nix {};

          # Spell checking (commented out due to false positives with acronyms)
          # Enable manually with: nix build .#checks.x86_64-linux.spell-check
          # spell-check = legacyPackages.callPackage ./nix/checks/spell-check.nix {};

          # TOML validation
          toml-check = legacyPackages.callPackage ./nix/checks/toml-check.nix {};
        };
      };
    in
      utils.lib.eachSystem systems forSystem // { overlay = localOverlay; };
}
