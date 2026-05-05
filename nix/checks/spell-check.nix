{ stdenv
, typos
, lib
}:

stdenv.mkDerivation {
  pname = "nix-book-spell-check";
  version = "0.0.1";

  src = lib.cleanSourceWith {
    src = ../..; # Root of the repo
    filter = path: type:
      let
        baseName = baseNameOf path;
      in
        # Include markdown files and config
        (lib.hasSuffix ".md" path) ||
        (baseName == ".typos.toml") ||
        (baseName == "src" && type == "directory");
  };

  nativeBuildInputs = [ typos ];

  buildPhase = ''
    echo "Checking for spelling errors..."
    typos --config .typos.toml .
  '';

  installPhase = ''
    mkdir -p $out
    echo "No spelling errors found" > $out/result
  '';

  doCheck = false;
}
