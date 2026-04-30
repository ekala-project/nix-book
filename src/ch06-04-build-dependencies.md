# Build Dependencies

Most software depends on other libraries, tools, or frameworks to build successfully.
In traditional package managers, dependencies are often implicit or managed through
system-wide package databases. Nix takes a different approach: all dependencies must
be explicitly declared and are isolated to each build.

This chapter covers how to specify build dependencies in nix packages, the different
types of dependency inputs, and how nix makes these dependencies available during
the build process.

## Adding Build Dependencies

Dependencies in `stdenv.mkDerivation` are specified through input attributes. The most
common are `buildInputs` and `nativeBuildInputs`:

```nix
{ stdenv, fetchurl, openssl, zlib, pkg-config }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";

  src = fetchurl {
    url = "https://example.com/example-1.0.tar.gz";
    sha256 = "...";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl zlib ];
}
```

In this example:
- `pkg-config` is a build tool needed to find other libraries
- `openssl` and `zlib` are libraries the software links against

## nativeBuildInputs vs buildInputs

The distinction between `nativeBuildInputs` and `buildInputs` becomes important
when cross-compiling, but the rule of thumb applies even for native builds:

### nativeBuildInputs

These are dependencies that run on the **build platform** (the machine doing the compilation).
They are tools used during the build process itself.

Common examples:
- Build tools: `cmake`, `meson`, `autoconf`, `automake`
- Code generators: `bison`, `flex`, `protobuf`
- Package discovery tools: `pkg-config`
- Documentation generators: `doxygen`, `sphinx`
- Compilers and interpreters: `python3`, `perl`, `rustc`

```nix
stdenv.mkDerivation {
  pname = "app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [
    cmake       # Build system
    pkg-config  # Finds libraries
    makeWrapper # Wrapper script generator
  ];
}
```

### buildInputs

These are dependencies for the **host platform** (the machine that will run the built software).
They are libraries and runtime dependencies that the built program will use.

Common examples:
- Libraries: `openssl`, `zlib`, `sqlite`
- GUI frameworks: `gtk3`, `qt5`
- Language runtimes: `python3` (when the built program uses it)

```nix
stdenv.mkDerivation {
  pname = "app";
  version = "1.0";
  src = ./.;

  buildInputs = [
    openssl    # Library linked into the binary
    zlib       # Library linked into the binary
    sqlite     # Database library
  ];
}
```

### Rule of Thumb

Ask yourself: "Does this dependency produce code that runs in my final binary,
or is it just a tool used during compilation?"

- If it's linked into your binary → `buildInputs`
- If it's a tool used during build → `nativeBuildInputs`

For native (non-cross) compilation, both lists work similarly, but using the
correct attribute makes your package more likely to work in all intended cases.

## Propagated Dependencies

Sometimes a package needs to ensure that its dependencies are also available to
anything that depends on it. This is where propagated inputs come in.

### propagatedBuildInputs

When package A depends on package B, and B's headers or modules must be available
when building anything that uses A, B should be in A's `propagatedBuildInputs`.

Common scenarios:
- Header-only C++ libraries
- Libraries whose headers include other library headers
- Python/Perl modules that import other modules
- Libraries that expose their dependencies through their API

```nix
# package: mylib
{ stdenv, boost, eigen }:

stdenv.mkDerivation {
  pname = "mylib";
  version = "1.0";
  src = ./.;

  # eigen is header-only and boost headers are exposed in mylib's API
  propagatedBuildInputs = [ boost eigen ];

  # Users of mylib will automatically get boost and eigen
}
```

Now when another package uses `mylib`:

```nix
# package: myapp
{ stdenv, mylib }:

stdenv.mkDerivation {
  pname = "myapp";
  version = "1.0";
  src = ./.;

  buildInputs = [ mylib ];
  # boost and eigen are automatically available during build
  # because mylib propagated them
}
```

### propagatedNativeBuildInputs

Similar to `propagatedBuildInputs`, but for build-time tools. This is less common,
but useful when a package provides build helpers that depend on other build tools.

```nix
{ stdenv, cmake, pkg-config, custom-cmake-modules }:

stdenv.mkDerivation {
  pname = "my-build-helper";
  version = "1.0";
  src = ./.;

  propagatedNativeBuildInputs = [ cmake custom-cmake-modules ];
  # Packages using my-build-helper will get cmake and custom-cmake-modules
}
```

### When to Propagate

Propagation should be used sparingly, as it increases the closure size of
dependent packages. Only propagate when:

1. The dependency's headers/modules are exposed in your public API
2. The dependency is required for anyone using your package
3. Not propagating would cause build failures in dependent packages

**Don't propagate** if the dependency is only used internally and not exposed
to users of your package.

## How Build Dependencies Are Made Available

Nix doesn't rely on a global package database or system paths. Instead, it
sets up environment variables that build tools use for dependency discovery.

### pkg-config

For libraries that provide `.pc` files, the `pkg-config` setup hook sets `PKG_CONFIG_PATH`:

```bash
# During build, nix automatically sets:
export PKG_CONFIG_PATH="/nix/store/xxx-openssl/lib/pkgconfig:/nix/store/yyy-zlib/lib/pkgconfig:..."

# This allows pkg-config to find dependencies:
$ pkg-config --cflags openssl
-I/nix/store/xxx-openssl/include

$ pkg-config --libs openssl
-L/nix/store/xxx-openssl/lib -lssl -lcrypto
```

Many build systems (`autoconf`, `cmake`, `meson`) use `pkg-config` automatically,
so this works transparently.

### CMake

For CMake packages, the `cmake` setup hook sets `CMAKE_PREFIX_PATH`:

```bash
export CMAKE_PREFIX_PATH="/nix/store/xxx-openssl:/nix/store/yyy-zlib:..."
```

This allows CMake's `find_package()` to locate dependencies:

```cmake
find_package(OpenSSL REQUIRED)
# CMake finds OpenSSL in CMAKE_PREFIX_PATH
```

**Note:** `NIXPKGS_CMAKE_PREFIX_PATH` was patched into Nixpkgs' CMake search path
traversal and now the preferred way to communicate nix dependencies. This was to
avoid clobbering `CMAKE_PREFIX_PATH` which can be altered during a build.

### Other Build Systems

Different ecosystems have their own conventions:

- **Python**: `PYTHONPATH` is set when using `buildPythonPackage`
- **Perl**: `PERL5LIB` is set when using `buildPerlPackage`
- **Go**: `GOPATH` is managed automatically

The key principle is that nix sets environment variables that toolchains
already understand, making the nix store paths discoverable.

## Common Dependency Patterns

### Libraries with Multiple Outputs

Many packages split their outputs into multiple parts to reduce closure sizes.
Common outputs include:

- `out` - The default output (binaries, non-development files)
- `dev` - Development files (headers, `.pc` files, CMake configs, propagated build inputs)
- `lib` - Shared libraries (sometimes separated from `out`)
- `bin` - Executables (sometimes separated from `out`)
- `man` - Man pages
- `doc` - Documentation

See [the multiple outputs section](./ch06-09-multiple-outputs.md) for more details.

### Referencing Specific Outputs

When a dependency has multiple outputs, you can specify which one you need:

```nix
{ stdenv, openssl, zlib }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  # Reference specific outputs explicitly
  nativeBuildInputs = [ pkg-config ];

  # Use dev output for headers during build
  buildInputs = [
    openssl.dev  # Headers and pkg-config files
    zlib.dev     # Headers
  ];

  # The lib/out outputs are automatically included in runtime dependencies
}
```

By default, when you reference a package in `buildInputs`, nix uses the `dev` output
if available (for build-time) and automatically tracks runtime references to `lib` or `out`.

### Helper Functions for Outputs

Nixpkgs provides helper functions in `lib` for working with outputs:

```nix
{ stdenv, lib, openssl, zlib }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  buildInputs = [
    (lib.getDev openssl)   # Get dev output
    (lib.getLib zlib)      # Get lib output
  ];

  # Other helpers:
  # lib.getBin pkg    - Get bin output
  # lib.getMan pkg    - Get man output
}
```

These helpers are more explicit than relying on default output selection and make
the intent clear.

### Conditional Dependencies

Dependencies can be conditional based on the platform or features:

```nix
{ stdenv, lib, openssl, util-linux }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  buildInputs = [ openssl ]
    ++ lib.optionals stdenv.isLinux [
      util-linux
    ];
}
```

The `lib.optionals` function only includes the list if the condition is true.

## Debugging Dependency Issues

When a build fails due to missing dependencies, here are some debugging techniques:

### Check What's Available

Enter a build environment to inspect what's available:

```bash
$ nix-shell '<nixpkgs>' -A your-package

# Check if a library is found
[nix-shell]$ pkg-config --exists openssl && echo "Found"

# Check available paths
[nix-shell]$ echo $PKG_CONFIG_PATH
[nix-shell]$ echo $CMAKE_PREFIX_PATH

# Try to find headers
[nix-shell]$ find -L $CMAKE_PREFIX_PATH -name "openssl.h" 2>/dev/null
```

### Verify Dependency Outputs

Check what outputs a dependency provides:

```bash
$ nix-instantiate --eval -E 'with import <nixpkgs> {}; openssl.outputs'
[ "bin" "dev" "out" "man" "doc" ]
```

If your build needs headers but you're only getting the `out` output, you may need
to explicitly request the `dev` output.

### Check Build Logs

Build logs show all environment variables set during the build:

```bash
$ nix-build your-package.nix 2>&1 | grep -A 10 "environment variables"

# Or build with verbose output
$ nix-build --verbose your-package.nix
```

## Example: Complete Package with Dependencies

Here's a realistic example showing various dependency patterns:

```nix
{ stdenv
, lib
, fetchFromGitHub
, cmake
, pkg-config
, openssl
, zlib
, curl
, sqlite
, boost
, qtbase
, wrapQtAppsHook
, enableGui ? true
}:

stdenv.mkDerivation rec {
  pname = "myapp";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "myapp";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ] ++ lib.optionals enableGui [
    wrapQtAppsHook
  ];

  buildInputs = [
    openssl.dev
    zlib
    curl
    sqlite
    boost
  ] ++ lib.optionals enableGui [
    qtbase
  ];

  cmakeFlags = [
    "-DENABLE_GUI=${if enableGui then "ON" else "OFF"}"
  ];

  meta = with lib; {
    description = "Example application with various dependencies";
    homepage = "https://example.com/myapp";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
```

This example demonstrates:
- Separating native and build inputs
- Using `.dev` output for headers
- Conditional dependencies based on features
- Using both build tools and libraries
- Proper use of helper hooks (wrapQtAppsHook)

## Summary

Understanding dependency management in nix requires grasping a few key concepts:

1. **Explicit dependencies**: All dependencies must be declared
2. **Build vs host**: `nativeBuildInputs` vs `buildInputs`
3. **Propagation**: When to use `propagatedBuildInputs`
4. **Environment variables**: How nix makes dependencies discoverable
5. **Multiple outputs**: Referencing `dev`, `lib`, or other outputs
6. **Helper functions**: Using `lib.getDev`, `lib.getLib`, etc.

With these tools, you can accurately express your package's dependency
requirements and create reproducible builds that work across different
platforms and configurations.
