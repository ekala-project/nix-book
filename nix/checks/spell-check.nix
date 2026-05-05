{ stdenv
, typos
, lib
, writeText
}:

let
  sourceRoot = ../..; # Root of the repo

  # Create the typos config inline
  typosConfig = writeText "typos.toml" ''
    [default.extend-words]
    FODs = "FODs"
    hda = "hda"
    crypted = "crypted"

    [files]
    extend-exclude = [
      "book/",
      "*.nix",
      "flake.lock",
    ]
  '';
in
stdenv.mkDerivation {
  pname = "nix-book-spell-check";
  version = "0.0.1";

  src = lib.cleanSourceWith {
    src = sourceRoot;
    filter = path: type:
      let
        baseName = baseNameOf path;
      in
        # Include markdown files and src directory
        (lib.hasSuffix ".md" path) ||
        (baseName == "src" && type == "directory");
  };

  nativeBuildInputs = [ typos ];

  buildPhase = ''
    echo "Checking for spelling errors..."
    typos --config ${typosConfig} .
  '';

  installPhase = ''
    mkdir -p $out
    echo "No spelling errors found" > $out/result
  '';

  doCheck = false;
}
