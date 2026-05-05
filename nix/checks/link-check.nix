{ mkShell
, lychee
, book
, cacert
}:

mkShell {
  name = "nix-book-link-check";

  nativeBuildInputs = [ lychee cacert ];

  # Set SSL_CERT_FILE for HTTPS requests
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  shellHook = ''
    echo "Checking links in built book..."
    lychee --config ${../../.lychee.toml} ${book}

    if [ $? -eq 0 ]; then
      echo "✓ All links are valid"
      exit 0
    else
      echo "✗ Link check failed"
      exit 1
    fi
  '';
}
