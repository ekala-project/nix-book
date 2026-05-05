{ stdenv
, lychee
, book
, lib
}:

stdenv.mkDerivation {
  pname = "nix-book-link-check";
  version = "0.0.1";

  src = lib.cleanSourceWith {
    src = ../..; # Root of the repo for .lychee.toml config
    filter = path: type:
      let
        baseName = baseNameOf path;
      in
        # Only include the lychee config
        (baseName == ".lychee.toml");
  };

  nativeBuildInputs = [ lychee ];

  buildPhase = ''
    # Run lychee on the built book HTML
    echo "Checking links in built book..."
    lychee --config .lychee.toml ${book}
  '';

  installPhase = ''
    mkdir -p $out
    echo "All links are valid" > $out/result
  '';

  doCheck = false;
}
