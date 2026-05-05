{ stdenv
, markdownlint-cli
, lib
}:

stdenv.mkDerivation {
  pname = "nix-book-markdown-lint";
  version = "0.0.1";

  src = lib.cleanSourceWith {
    src = ../..; # Root of the repo
    filter = path: type:
      let
        baseName = baseNameOf path;
      in
        # Include markdown files and config
        (lib.hasSuffix ".md" path) ||
        (baseName == ".markdownlint.json") ||
        (baseName == "src" && type == "directory");
  };

  nativeBuildInputs = [ markdownlint-cli ];

  buildPhase = ''
    echo "Linting markdown files..."
    markdownlint --config .markdownlint.json 'src/**/*.md'
  '';

  installPhase = ''
    mkdir -p $out
    echo "All markdown files are properly formatted" > $out/result
  '';

  doCheck = false;
}
