final: prev: {
  nix-book = prev.callPackage ./book.nix { };

  devShell = prev.mkShell {
    inputsFrom = [ final.nix-book ];

    packages = with prev; [
      # Book building
      mdbook

      # Linting and checking tools
      lychee            # Link checker
      markdownlint-cli  # Markdown linter
      typos             # Spell checker
      taplo             # TOML validator
    ];

    shellHook = ''
      echo "Nix Book development environment"
      echo "Available commands:"
      echo "  mdbook serve       - Start development server"
      echo "  mdbook build       - Build the book"
      echo "  nix flake check    - Run all checks"
      echo ""
      echo "Individual checks:"
      echo "  lychee --config .lychee.toml book/     - Check links"
      echo "  markdownlint --config .markdownlint.json 'src/**/*.md' - Lint markdown"
      echo "  typos --config .typos.toml .           - Check spelling"
      echo "  taplo check book.toml                   - Validate TOML"
    '';
  };
}
