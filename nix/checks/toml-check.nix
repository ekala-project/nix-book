{ stdenv
, taplo
, lib
}:

stdenv.mkDerivation {
  pname = "nix-book-toml-check";
  version = "0.0.1";

  src = lib.cleanSourceWith {
    src = ../..; # Root of the repo
    filter = path: type:
      let
        baseName = baseNameOf path;
      in
        # Include TOML files
        (lib.hasSuffix ".toml" path);
  };

  nativeBuildInputs = [ taplo ];

  buildPhase = ''
    echo "Validating TOML files..."
    # Check book.toml
    taplo check book.toml

    # Also check any other TOML files
    find . -name "*.toml" -type f -exec taplo check {} \;
  '';

  installPhase = ''
    mkdir -p $out
    echo "All TOML files are valid" > $out/result
  '';

  doCheck = false;
}
