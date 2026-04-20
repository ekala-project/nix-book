# Rust

Rust has become increasingly popular for systems programming, offering memory safety
without garbage collection. Rust is a favorite amongst many for it's safety, speed,
and correctness qualities.

## Rust and Nix: special concerns

### Cargo and dependency management

Rust uses Cargo for dependency management, which downloads dependencies from crates.io
at build time. This conflicts with Nix's requirement for reproducible, offline builds.
Nix solves this by:

1. **Pre-fetching dependencies**: Nix downloads all Cargo dependencies before the build
2. **Vendoring**: Dependencies are placed in a local directory that Cargo uses instead of downloading
3. **Hash verification**: A hash of all dependencies ensures reproducibility

This means Rust packages in Nix require an additional hash (`cargoHash` or `cargoSha256`)
that covers all dependencies listed in `Cargo.lock`.

### Cargo.lock is essential

Unlike development where `Cargo.lock` may be gitignored for libraries, Nix requires
`Cargo.lock` to determine exact dependency versions. If a project doesn't ship
`Cargo.lock`, you'll need to generate it.

### Build artifacts and incremental compilation

Cargo caches build artifacts for incremental compilation. In Nix:
- Each build starts fresh (no incremental compilation)
- Build artifacts from dependencies are cached separately
- This ensures reproducibility but may increase build times

## Basic Rust package

Rust packages in nixpkgs use `rustPlatform.buildRustPackage`. Here's a minimal example:

```nix
{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "ripgrep";
  version = "14.0.3";

  src = fetchFromGitHub {
    owner = "BurntSushi";
    repo = "ripgrep";
    rev = version;
    sha256 = "sha256-...";
  };

  cargoHash = "sha256-...";

  meta = with lib; {
    description = "A line-oriented search tool";
    homepage = "https://github.com/BurntSushi/ripgrep";
    license = licenses.unlicense;
  };
}
```

The `buildRustPackage` function handles:
- Setting up the Rust toolchain
- Fetching and vendoring Cargo dependencies
- Running `cargo build --release`
- Installing binaries to `$out/bin`

## Common Rust build options

### cargoHash vs cargoSha256

Two attributes are available for specifying the dependency hash:

**cargoHash** (preferred, modern):
```nix
cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

**cargoSha256** (legacy, still supported):
```nix
cargoSha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

To get the hash, set it to an empty string or fake hash and let Nix tell you the correct one:

```nix
cargoHash = "";  # or lib.fakeHash
```

### Cargo build flags

Control how Cargo builds the package:

```nix
# Build only specific binaries
cargoBuildFlags = [ "--bin" "main-binary" ];

# Pass features to Cargo
buildFeatures = [ "feature1" "feature2" ];
buildNoDefaultFeatures = true;

# Or use cargoFlags for full control
cargoFlags = [ "--all-features" ];
```

### Testing

Rust tests run by default during the check phase:

```nix
# Disable tests entirely
doCheck = false;

# Skip specific tests
checkFlags = [
  "--skip test_requires_network"
  "--skip integration_test"
];

# Test only specific packages in a workspace
cargoTestFlags = [ "--package" "subcrate" ];
```

### Cargo workspaces

For projects with multiple crates in a workspace:

```nix
# Build all workspace members
cargoBuildFlags = [ "--workspace" ];

# Or build specific members
cargoBuildFlags = [ "--package" "crate1" "--package" "crate2" ];
```

### Native dependencies

Rust projects often link to C libraries:

```nix
{ lib, rustPlatform, fetchFromGitHub, pkg-config, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "cargo-audit";
  version = "0.18.3";

  src = fetchFromGitHub {
    owner = "rustsec";
    repo = "rustsec";
    rev = "cargo-audit/v${version}";
    sha256 = "sha256-...";
  };

  cargoHash = "sha256-...";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # Set environment variables for build scripts
  env.OPENSSL_NO_VENDOR = 1;

  meta = with lib; {
    description = "Audit Cargo.lock for security vulnerabilities";
    license = licenses.asl20;
  };
}
```

## Common issues and fixes

### Missing Cargo.lock

If the source doesn't include `Cargo.lock`:

```nix
postPatch = ''
  # Generate Cargo.lock if missing
  cargo generate-lockfile
'';

# Or use cargoLock attribute to specify it separately
cargoLock = {
  lockFile = ./Cargo.lock;
};
```

### Build script failures

Cargo build scripts (`build.rs`) sometimes have issues in Nix:

```nix
# Disable specific build scripts
postPatch = ''
  # Remove problematic build script
  rm subcrate/build.rs
'';

# Set environment variables build scripts need
env.SOME_VAR = "value";

# Provide tools build scripts expect
nativeBuildInputs = [ cmake protobuf ];
```

### Linking errors

When Rust code fails to link against system libraries:

```nix
# Ensure pkg-config can find libraries
nativeBuildInputs = [ pkg-config ];
buildInputs = [ openssl zlib ];

# Or set environment variables manually
env.PKG_CONFIG_PATH = "${lib.getDev openssl}/lib/pkgconfig";

# For libraries that don't use pkg-config
preBuild = ''
  export LIBRARY_PATH="${lib.getLib openssl}/lib:$LIBRARY_PATH"
'';
```

### Vendoring issues with git dependencies

Cargo dependencies from git repositories need special handling:

```nix
cargoLock = {
  lockFile = ./Cargo.lock;
  outputHashes = {
    "some-crate-0.1.0" = "sha256-...";
  };
};
```

### Tests require network or filesystem access

Disable problematic tests:

```nix
# Skip network-dependent tests
checkFlags = [
  "--skip test_downloads"
  "--skip test_api"
];

# Or disable the check phase entirely
doCheck = false;
```

### Cross-compilation

Rust has excellent cross-compilation support. Specify the target:

```nix
# Set in the derivation
cargoExtraArgs = [ "--target" "x86_64-unknown-linux-musl" ];

# Or configure via environment
env.CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
```

### Binary size optimization

Reduce binary size by stripping debug info:

```nix
# Strip debug symbols (usually done by default)
dontStrip = false;

# Use release profile optimizations
cargoFlags = [ "--profile" "release" ];

# Or configure in Cargo.toml instead
```

## Detailed example

Here's a comprehensive example of a Rust CLI application with native dependencies,
tests, and multiple binaries:

```nix
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, installShellFiles
, stdenv
, openssl
, sqlite
, zlib
}:

rustPlatform.buildRustPackage rec {
  pname = "example-rust-cli";
  version = "2.5.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "rust-cli";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  cargoHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

  nativeBuildInputs = [
    pkg-config
    installShellFiles
  ];

  buildInputs = [
    openssl
    sqlite
    zlib
  ];

  # Build only the main binary, not helper tools
  cargoBuildFlags = [ "--bin" "example-cli" ];

  # Enable all features except "unstable"
  buildNoDefaultFeatures = true;
  buildFeatures = [ "tls" "sqlite" "compression" ];

  # Skip tests that require network access
  checkFlags = [
    "--skip=integration::test_remote_api"
    "--skip=sync::test_download"
  ];

  # Don't run doc tests as they may be flaky
  cargoTestFlags = [ "--lib" "--bins" ];

  # Set environment variables for the build
  env = {
    OPENSSL_NO_VENDOR = 1;
    ZSTD_SYS_USE_PKG_CONFIG = 1;
  };

  # Generate Cargo.lock if it's missing (usually it should be committed)
  # postPatch = ''
  #   cargo generate-lockfile
  # '';

  postInstall = ''
    # Install shell completions
    installShellCompletion --cmd example-cli \
      --bash <($out/bin/example-cli completions bash) \
      --fish <($out/bin/example-cli completions fish) \
      --zsh <($out/bin/example-cli completions zsh)

    # Install man page
    installManPage docs/example-cli.1
  '';

  meta = with lib; {
    description = "Example Rust CLI tool for file management";
    longDescription = ''
      A comprehensive command-line tool written in Rust, demonstrating
      best practices for packaging Rust applications in nixpkgs including
      native dependencies, feature flags, and shell completion installation.
    '';
    homepage = "https://github.com/example/rust-cli";
    changelog = "https://github.com/example/rust-cli/releases/tag/v${version}";
    license = licenses.mit;
    # Only build on platforms where all dependencies are available
    platforms = platforms.unix;
    # Mark as broken on specific platforms if needed
    # broken = stdenv.isDarwin;
  };
}
```

This example demonstrates:
- Using `buildRustPackage` for a CLI application
- Cross-platform dependencies (macOS frameworks)
- Native library dependencies (OpenSSL, SQLite, zlib)
- Selective binary building with `cargoBuildFlags`
- Feature flag management
- Test filtering for problematic tests
- Environment variable configuration for build scripts
- Post-install tasks (shell completions, man pages)
- Comprehensive metadata with platform constraints

## Working with Cargo workspaces

For projects with multiple crates:

```nix
rustPlatform.buildRustPackage rec {
  pname = "workspace-project";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-...";
  };

  cargoHash = "sha256-...";

  # Build specific workspace members
  cargoBuildFlags = [
    "--package" "main-app"
    "--package" "helper-tool"
  ];

  # Run tests for all workspace members
  cargoTestFlags = [ "--workspace" ];

  # Install binaries from multiple crates
  postInstall = ''
    install -Dm755 target/release/main-app $out/bin/main-app
    install -Dm755 target/release/helper-tool $out/bin/helper-tool
  '';

  meta = with lib; {
    description = "Multi-crate Rust workspace";
    license = licenses.asl20;
  };
}
```

## Using buildRustCrate for advanced cases

For more control over the build process, use `buildRustCrate` (lower-level):

```nix
{ lib, rustPlatform }:

rustPlatform.buildRustCrate {
  pname = "mycrate";
  version = "1.0.0";
  src = ./.;

  # Specify dependencies manually
  dependencies = [
    # ... other crates
  ];
}
```

This is rarely needed; `buildRustPackage` handles most use cases.

## Summary

Rust packaging in Nix leverages Cargo while maintaining reproducibility:
- Use `rustPlatform.buildRustPackage` for most Rust projects
- Specify `cargoHash` to lock dependency versions
- Ensure `Cargo.lock` is present in the source
- Use `pkg-config` and list native dependencies in `buildInputs`
- Control features with `buildFeatures` and `buildNoDefaultFeatures`
- Platform-specific dependencies (like macOS frameworks) should use conditionals
- Check existing nixpkgs Rust packages for patterns and solutions
