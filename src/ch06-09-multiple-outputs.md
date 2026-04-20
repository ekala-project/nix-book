# Multiple Outputs

By default, a nix package produces a single output in the nix store. However, many
packages can be split into multiple outputs, each containing a different subset of
files. This splitting serves two critical purposes: reducing closure sizes and
enabling cross-compilation.

This chapter explains why multiple outputs exist, how to create and use them, and
common pitfalls to avoid.

## Why Multiple Outputs?

### Closure Size Reduction

The primary motivation for multiple outputs is reducing the runtime closure size of
packages. Consider a typical library package that contains:

- Compiled shared libraries (`.so` or `.dylib` files)
- Header files (`.h` files)
- pkg-config files (`.pc` files)
- Static libraries (`.a` files)
- Documentation and man pages
- Binaries and utilities

When you build an application that depends on this library, you typically only need
the shared libraries at runtime. The headers, static libraries, and documentation
are only needed during the build.

This can reduce runtime closures by 30-50% for complex applications, which means:
- Faster downloads from binary caches
- Less disk usage on deployed systems
- Smaller Docker images
- Faster deployments and updates

### Cross-Compilation Support

Multiple outputs also enable cleaner cross-compilation. When cross-compiling, you
need to distinguish between:

- **Build platform** tools: Programs that run on the build machine
- **Host platform** libraries: Libraries for the target architecture

With multiple outputs, the `bin` output can be marked for the build platform while
`lib` and `out` are for the host platform. This ensures build tools don't get
mixed into the target system's closure.

## Common Output Types

Nixpkgs uses standard output names with conventional purposes:

| Output | Contents | Purpose |
|--------|----------|---------|
| `out` | Default output | Catch-all for files not in other outputs |
| `dev` | Development files | Headers, pkg-config, CMake configs, static libs |
| `lib` | Shared libraries | `.so`, `.dylib`, `.dll` files |
| `bin` | Executables | Binary programs |
| `man` | Man pages | Documentation in man format |
| `doc` | Documentation | General documentation, HTML, PDFs |
| `info` | Texinfo docs | GNU Info documentation |
| `devdoc` | Developer docs | API documentation |
| `include` | C/C++ Headers | Decouple headers from dev (still being adopted circa 2026) |

**Note**: If only one or two outputs exist, `out` usually contains everything. The
split only happens when it provides meaningful closure size reduction.

## Using Multiple Outputs

### Referencing Outputs as a Consumer

When a package has multiple outputs, you can reference specific ones:

```nix
{ stdenv, openssl, zlib, pkg-config }:

stdenv.mkDerivation {
  pname = "myapp";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    # Reference the dev output for headers and pkg-config files
    # Generally this is not needed to be done explicitly by users and instead
    # should pass the package instead of an output.
    openssl.dev
    zlib.dev

    # The library outputs are automatically pulled in at runtime
    # You don't usually need to specify them explicitly
  ];
}
```

The nix build system automatically handles runtime dependencies:
- During build: `dev` output provides headers
- At runtime: Only `lib` or `out` are included in the closure

### Default Output Selection

When you reference a package without specifying an output, nix uses defaults:

```nix
buildInputs = [ openssl ];
# In buildInputs, defaults to openssl.dev (if it exists)

propagatedBuildInputs = [ openssl ];
# Also defaults to .dev for propagation
```

These defaults are context-sensitive and designed to "do the right thing" for
typical use cases.

### Explicit Output Selection

For clarity or special cases, be explicit:

```nix
buildInputs = [
  openssl.dev   # Headers for compilation
];

# Force a specific output
preInstall = ''
  cp ${openssl.out}/lib/libssl.so $out/lib/
'';
```

### Helper Functions

Use nixpkgs helper functions for clearer intent. These will return the `out`
output if the prefered output does not exist.

```nix
{ lib, openssl, curl, postgresql }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  buildInputs = [
    (lib.getDev openssl)      # Development files
    (lib.getLib curl)          # Shared libraries
    (lib.getBin postgresql)    # Executables
  ];
}
```

Available helpers:
- `lib.getDev pkg` - Get development output
- `lib.getLib pkg` - Get library output
- `lib.getBin pkg` - Get binary output
- `lib.getMan pkg` - Get man pages
- `lib.getDevMan pkg` - Get dev and man outputs

## Creating Multiple Outputs

### Basic Output Declaration

To split a package into multiple outputs, declare them in the `outputs` attribute:

```nix
stdenv.mkDerivation {
  pname = "mylib";
  version = "1.0";
  src = ./.;

  # Declare the outputs
  outputs = [ "out" "dev" "doc" ];

  # The first output in the list becomes the default
}
```

**Important**: The first output in the list is the default. Typically, `out` should
be first unless you have a specific reason otherwise. For example, `curl` has
bin as the default since it's more commonly used as a command than a library.

### Automatic Output Splitting

Stdenv provides automatic output splitting for common cases. Simply declaring
`outputs = [ "out" "dev" ];` will automatically:

1. Move `include/` to `$dev`
2. Move `.pc` files to `$dev`
3. Move CMake config files to `$dev`
4. Move static libraries to `$dev`
5. Keep shared libraries in `$out` or `$lib`

Example with automatic splitting:

```nix
{ stdenv, cmake }:

stdenv.mkDerivation {
  pname = "mylib";
  version = "1.0";
  src = ./.;

  outputs = [ "out" "dev" ];

  nativeBuildInputs = [ cmake ];

  # After installation, stdenv automatically splits:
  # $out/lib/*.so -> stays in $out
  # $out/include/* -> moved to $dev/include
  # $out/lib/pkgconfig/*.pc -> moved to $dev/lib/pkgconfig
  # $out/lib/*.a -> moved to $dev/lib
}
```

**Note:** This can sometimes cause issues when the contents of a `.cmake` or `.pc`
are not updated to where the files are moved.

### Manual Output Assignment

For custom file placement, use `moveToOutput`:

```nix
stdenv.mkDerivation {
  pname = "mylib";
  version = "1.0";
  src = ./.;

  outputs = [ "out" "dev" "doc" "examples" ];

  postInstall = ''
    # Move headers to dev output
    moveToOutput "include" "$dev"

    # Move documentation to doc output
    moveToOutput "share/doc" "$doc"

    # Move examples to their own output
    mkdir -p $examples/share
    mv $out/share/examples $examples/share/
  '';
}
```

`moveToOutput` ensures that:
1. The path is actually moved (not copied)
2. Any references in moved files are updated
3. Parent directories are cleaned up if empty

### Output-Specific Paths

Each output is bound to a variable during the build, similar to `$out`:

```nix
outputs = [ "out" "dev" "bin" "doc" ];

installPhase = ''
  # Install shared libraries to main output
  mkdir -p $out/lib
  cp *.so $out/lib/

  # Install headers to dev output
  mkdir -p $dev/include
  cp *.h $dev/include/

  # Install binaries to bin output
  mkdir -p $bin/bin
  cp mytool $bin/bin/

  # Install docs to doc output
  mkdir -p $doc/share/doc
  cp -r docs/* $doc/share/doc/
'';
```

## The placeholder Function

When you need to reference an output path during evaluation but before the actual
store path is known, use `placeholder`:

```nix
{ stdenv }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  outputs = [ "out" "dev" ];

  # WRONG: $dev is empty during some phases
  configureFlags = [
    "--includedir=$dev/include"  # This won't work!
  ];

  # CORRECT: Use placeholder
  configureFlags = [
    "--includedir=${placeholder "dev"}/include"
  ];

  # Not possible to communicate during evaluation without placeholder
  passthru.EXAMPLE_HOME = "${placeholder "out"}/share";
}
```

### Why placeholder Is Needed

During the build, output paths aren't yet determined. The hash of the output depends
on the build inputs and process. Using `$dev` directly might expand to an empty
string or incorrect value during early build phases.

`placeholder` generates a temporary string that stdenv replaces with the actual
output path at the right time.

### Common placeholder Usage

```nix
outputs = [ "out" "dev" "lib" ];

# In configure flags
configureFlags = [
  "--prefix=${placeholder "out"}"
  "--includedir=${placeholder "dev"}/include"
  "--libdir=${placeholder "lib"}/lib"
];

# In CMake flags
cmakeFlags = [
  "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
  "-DCMAKE_INSTALL_INCLUDEDIR=${placeholder "dev"}/include"
];

# In makeFlags
makeFlags = [
  "PREFIX=${placeholder "out"}"
  "INCLUDEDIR=${placeholder "dev"}/include"
];
```

### When NOT to Use placeholder

You don't need `placeholder` in phases that run after the outputs are created:

```nix
outputs = [ "out" "dev" ];

# GOOD: installPhase runs late, $dev is available
installPhase = ''
  mkdir -p $dev/include
  cp *.h $dev/include/
'';

# GOOD: postInstall also has outputs available
postInstall = ''
  moveToOutput "include" "$dev"
'';
```

## Advanced Multiple Output Patterns

    # User-facing binaries stay in out
    # (out is the default, so users get these)

    # Developer tools go to bin
    mkdir -p $bin/bin
    mv $out/bin/toolkit-config $bin/bin/
    mv $out/bin/toolkit-debug $bin/bin/
  '';
}
```

### Libraries with Optional Features

Split optional features into separate outputs:

```nix
stdenv.mkDerivation {
  pname = "multimedia-lib";
  version = "1.0";
  src = ./.;

  outputs = [ "out" "dev" "plugins" ];

  postInstall = ''
    # Core library in out
    # Headers in dev (automatic)

    # Optional plugins in separate output
    mkdir -p $plugins/lib/plugins
    mv $out/lib/plugins/* $plugins/lib/plugins/
  '';
}
```

Users who don't need plugins won't download them.

## Debugging Multiple Outputs

### Check What Outputs Exist

```bash
$ nix-instantiate --eval -E 'with import <nixpkgs> {}; openssl.outputs'
[ "bin" "dev" "out" "man" "doc" ]
```

### See What's in Each Output

```bash
$ nix-build '<nixpkgs>' -A openssl.dev
$ tree result/
result/
├── include
│   └── openssl
│       ├── aes.h
│       ├── ...
└── lib
    └── pkgconfig
        ├── libcrypto.pc
        └── libssl.pc

$ nix-build '<nixpkgs>' -A openssl.out
$ tree result/
result/
└── lib
    ├── libcrypto.so.3
    └── libssl.so.3
```

### Building all outputs

In nix 1.0 and 2.0, there's a psuedo `all` attr which build all outputs:

```
$ nix-build -A openssl.all
...
/nix/store/uuu-openssl-3.6.1-bin
/nix/store/vvv-openssl-3.6.1-dev
/nix/store/www-openssl-3.6.1
/nix/store/xxx-openssl-3.6.1-man
/nix/store/yyy-openssl-3.6.1-doc
/nix/store/zzz-openssl-3.6.1-debug
```

In nix 3.0 (flakes), the `^*` syntax is used to build all outputs:

```
$ nix build .#openssl.^* --print-out-paths
...
/nix/store/uuu-openssl-3.6.1-bin
/nix/store/vvv-openssl-3.6.1-dev
/nix/store/www-openssl-3.6.1
/nix/store/xxx-openssl-3.6.1-man
/nix/store/yyy-openssl-3.6.1-doc
/nix/store/zzz-openssl-3.6.1-debug
```

## Common Pitfalls

### Forgetting placeholder in Configure Flags

```nix
# BAD: $dev will get escaped
configureFlags = [ "--includedir=$dev/include" ];

# GOOD: Use placeholder
configureFlags = [ "--includedir=${placeholder "dev"}/include" ];
```

### Wrong Default Output

```nix
# BAD: dev is default, users get headers by default
outputs = [ "dev" "out" ];

# GOOD: out is default
outputs = [ "out" "dev" ];
```

The first output is what users get when they install the package.

### Circular Dependencies Between Outputs

```nix
# BAD: dev references out, out references dev
outputs = [ "out" "dev" ];

postInstall = ''
  echo "${placeholder "out"}" > $dev/dep
  echo "${placeholder "dev"}" > $out/dep
'';
```

Outputs should form a directed acyclic graph (DAG). Typically:
- `dev` can reference `out` or `lib`
- `out` should not reference `dev`
- `bin` can reference `lib` or `out`

### Not using dev with propagated inputs

If a `dev` output is missing, then propagated inputs will have their closure
added to `out`. In some cases, this can bloat the outputs by several GBs.

```nix
# BAD: Defaulting to out for propagating inputs
outputs = [ "out" ];

# openssl.dev is added to $out/nix-support/propagated-build-inputs
propagatedBuildInputs = [ openssl ];


# GOOD: Use dev output
outputs = [ "out" "dev" ];

# openssl.dev is added to $dev/nix-support/propagated-build-inputs
propagatedBuildInputs = [ openssl ];
```

### Not Using moveToOutput

```nix
# BAD: Files stay in out, defeating the purpose
outputs = [ "out" "dev" ];

postInstall = ''
  mkdir -p $dev/include
  cp $out/include/* $dev/include/  # Copied, not moved!
  # Files still in $out/include
'';

# GOOD: Use moveToOutput
postInstall = ''
  moveToOutput "include" "$dev"  # Properly moved
'';
```

### Hardcoding Output Paths

```nix
# BAD: Assumes specific output structure, this always be incorrect as it will affect the drv output paths
postPatch = ''
  substituteInPlace config.sh \
    --replace '/usr/include' '/nix/store/xxx-mylib-dev/include'
'';

# GOOD: Use placeholder
postPatch = ''
  substituteInPlace config.sh \
    --replace '/usr/include' '${placeholder "dev"}/include'
'';
```

## When to Use Multiple Outputs

Use multiple outputs when:
1. **Large headers or docs**: Headers/docs are >5MB and rarely needed at runtime
2. **Optional components**: Some users need plugins/tools, others don't
3. **Cross-compilation**: Separating build tools from target libraries
4. **Clear boundaries**: Natural separation exists (libs vs bins vs docs)

Don't use multiple outputs when:
2. **Everything needed together**: No clear separation of concerns
3. **Single-purpose packages**: Only produces one type of file

## Complete Example

Here's a realistic library package with multiple outputs:

```nix
{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, doxygen
}:

stdenv.mkDerivation rec {
  pname = "graphics-lib";
  version = "2.5.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "graphics-lib";
    rev = "v${version}";
    sha256 = "sha256-...";
  };

  # Declare outputs: out is default for end users
  outputs = [ "out" "dev" "doc" "examples" ];

  nativeBuildInputs = [
    cmake
    pkg-config
    doxygen
  ];

  cmakeFlags = [
    "-DBUILD_EXAMPLES=ON"
    # The CMake setup hook will do these two definitions for you, but
    # are included for demonstration purposes
    "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
    "-DCMAKE_INSTALL_INCLUDEDIR=${placeholder "dev"}/include"
  ];

  # Build API documentation
  postBuild = ''
    doxygen Doxyfile
  '';

  postInstall = ''
    # Documentation goes to doc output
    mkdir -p $doc/share/doc/graphics-lib
    cp -r html $doc/share/doc/graphics-lib/

    # Examples go to their own output
    mkdir -p $examples/share/graphics-lib
    mv $out/share/examples $examples/share/graphics-lib/

    # Automatic splitting moves:
    # - Headers to $dev/include
    # - .pc files to $dev/lib/pkgconfig
    # - Static libs to $dev/lib
    # - Shared libs stay in $out/lib
  '';

  meta = with lib; {
    description = "Graphics library with multiple outputs";
    homepage = "https://github.com/example/graphics-lib";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
```

Users of this library:
```nix
# Building an application: gets dev + out in closure during build
buildInputs = [ graphics-lib ];

# Only needs out at runtime (libraries)
# Runtime closure: graphics-lib.out (~2MB)
# Development closure: graphics-lib.dev (~10MB) + graphics-lib.out

# Documentation isn't pulled unless explicitly requested
# Documentation closure: graphics-lib.doc (~50MB)
```

## Summary

Multiple outputs are a powerful feature for:

1. **Reducing closure sizes**: Runtime closures can be 30-50% smaller
2. **Cleaner cross-compilation**: Separate build tools from target artifacts
3. **Flexible deployments**: Choose what to include in different contexts

Key concepts:
- **outputs attribute**: Declares what outputs exist
- **placeholder function**: Reference outputs before paths are known
- **moveToOutput**: Correctly split files between outputs
- **Default output**: First in `outputs` list is what users get by default
- **Helper functions**: `lib.getDev`, `lib.getLib`, etc. for clarity

Used wisely, multiple outputs significantly reduce resource usage in nix systems
without compromising functionality.
