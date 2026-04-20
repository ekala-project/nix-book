# Shell Hooks and Toolchain Support

In [the previous chapters](./ch06-02-stdenv.md), we've seen that `stdenv.mkDerivation`
provides defaults for building software with Make and autotools. However, many modern
projects use different build systems like CMake, Meson, or Bazel. Rather than requiring
package authors to manually configure these tools for every package, nix uses a mechanism
called "setup hooks" to automatically adapt the build environment.

This chapter explains how setup hooks work, how they modify the build process, and how
to use common build systems with nix.

## What Are Setup Hooks?

Setup hooks are shell scripts that run during the build setup phase, before any of the
standard phases like `unpackPhase` or `configurePhase` execute. They allow packages to
inject logic that modifies the build environment for themselves and any package that
depends on them.

Setup hooks are particularly useful for:
- Configuring environment variables for build tools
- Adding new build phases or modifying existing ones
- Registering files for automatic processing
- Setting up language-specific build environments

When a package is added to `nativeBuildInputs`, its setup hook (if it has one) will
automatically run during the build setup. This makes build tool integration seamless.

### How Setup Hooks Work

During the setup phase (before any user-defined or standard phases run), nix sources
the setup hooks of all packages in `nativeBuildInputs` and `propagatedNativeBuildInputs`.
These hooks can:

1. **Set environment variables** - Configure paths, flags, or tool-specific settings
2. **Modify phases** - Append to or replace phase implementations
3. **Register hooks** - Add pre/post hooks to existing phases
4. **Define functions** - Provide utilities for use in build scripts

The key insight is that setup hooks run in the same shell environment where your build
phases will execute, so any variables or functions they define are available throughout
the build.

## A Simple Example: pkg-config

Before diving into complex build systems, let's look at a simple setup hook. The
`pkg-config` package provides a setup hook that sets `PKG_CONFIG_PATH`:

```nix
{ stdenv, pkg-config, openssl }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # pkg-config's setup hook automatically sets PKG_CONFIG_PATH
  # to include openssl's .pc files
}
```

The setup hook (simplified) does something like:

```bash
# From pkg-config's setup hook
addPkgConfigPath() {
  addToSearchPath PKG_CONFIG_PATH $1/lib/pkgconfig
  addToSearchPath PKG_CONFIG_PATH $1/share/pkgconfig
}

addEnvHooks "$hostOffset" addPkgConfigPath
```

This automatically adds the `lib/pkgconfig` and `share/pkgconfig` directories of all
`buildInputs` to `PKG_CONFIG_PATH`, making libraries discoverable.

## CMake: A Detailed Example

CMake is one of the most popular build systems for C/C++ projects. Let's see how its
setup hook modifies `stdenv.mkDerivation` behavior.

### Basic CMake Package

```nix
{ stdenv, cmake, fetchurl }:

stdenv.mkDerivation {
  pname = "example-cmake-project";
  version = "1.0";

  src = fetchurl {
    url = "https://example.com/project-1.0.tar.gz";
    sha256 = "...";
  };

  nativeBuildInputs = [ cmake ];
}
```

By simply adding `cmake` to `nativeBuildInputs`, the setup hook automatically:
1. Changes `configurePhase` to run `cmake` instead of `./configure`
2. Sets up `CMAKE_PREFIX_PATH` (actually `NIXPKGS_CMAKE_PREFIX_PATH`) to find dependencies
3. Configures the install prefix to `$out`
4. Sets up appropriate build types and CMake flags

## Meson: Modern Build System

Meson is another popular build system that emphasizes speed and user-friendliness.
Like CMake, it has a setup hook that integrates with `stdenv.mkDerivation`.

### Basic Meson Package

```nix
{ stdenv, meson, ninja, pkg-config, glib }:

stdenv.mkDerivation {
  pname = "example-meson-project";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ glib ];

  # Meson's setup hook handles the rest
}
```

**Note**: Meson requires Ninja as the actual build backend, so both `meson` and `ninja`
should be in `nativeBuildInputs`.

### What Meson's Setup Hook Provides

The Meson setup hook:
1. Replaces `configurePhase` with `meson setup`
2. Sets the build directory to `build` by default
3. Configures the install prefix to `$out`
4. Sets up cross-compilation parameters automatically

The configure phase becomes:

```bash
meson setup build --prefix=$out $mesonFlags
```

And the build phase uses:

```bash
ninja -C build
```

## Writing Custom Setup Hooks

Sometimes you need to create your own setup hook for a custom build tool or to provide
reusable build logic.

### Setup Hook File Location

A package can provide a setup hook by placing a script at:
```
$out/nix-support/setup-hook
```

### Example: Custom Build Tool

```nix
{ stdenv }:

stdenv.mkDerivation {
  pname = "my-build-tool";
  version = "1.0";
  src = ./.;

  installPhase = ''
    mkdir -p $out/bin $out/nix-support
    cp my-build-tool $out/bin/

    # Create setup hook
    cat > $out/nix-support/setup-hook <<'EOF'
    # This hook runs when my-build-tool is in nativeBuildInputs

    # Add our tool to PATH
    addToSearchPath PATH @out@/bin

    # Set environment variables
    export MY_BUILD_TOOL_HOME=@out@

    # Customize the build phase
    myBuildToolBuildPhase() {
      echo "Running my-build-tool..."
      my-build-tool build $myBuildToolFlags
    }

    # Use this as the build phase if BUILD_TOOL variable is set
    if [ -n "$USE_MY_BUILD_TOOL" ]; then
      buildPhase=myBuildToolBuildPhase
    fi
    EOF

    # Substitute @out@ with actual store path
    substituteInPlace $out/nix-support/setup-hook \
      --replace @out@ $out
  '';
}
```

Now packages can use it:

```nix
{ stdenv, my-build-tool }:

stdenv.mkDerivation {
  pname = "project";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ my-build-tool ];

  # The setup hook automatically configures the environment
  USE_MY_BUILD_TOOL = true;
  myBuildToolFlags = [ "--optimize" "--verbose" ];
}
```

### Common Setup Hook Patterns

Setup hooks often use these patterns:

#### Adding to Search Paths

```bash
# Add directory to PATH for all dependencies
addToSearchPathWithCustom() {
  addToSearchPath PATH $1/bin
  addToSearchPath LIBRARY_PATH $1/lib
}

addEnvHooks "$hostOffset" addToSearchPathWithCustom
```

#### Modifying Phases

```bash
# Append to an existing phase
postConfigureHooks+=('echo "Configure completed"')

# Or replace a phase entirely
configurephase=myCustomConfigurePhase
```

#### Registering File Types

```bash
# Process all .proto files automatically
processProto() {
  for proto in "$1"/**/*.proto; do
    protoc "$proto"
  done
}

addEnvHooks "$hostOffset" processProto
```

## The shellHook Attribute

The `shellHook` attribute in `mkDerivation` is different from setup hooks. It only
runs when entering a `nix-shell` development environment, not during builds:

```nix
stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ cmake ];

  # This only runs in nix-shell, not during nix-build
  shellHook = ''
    echo "Welcome to the development environment!"
    echo "CMake version: $(cmake --version | head -1)"
    echo "Build directory: $(pwd)"
  '';
}
```

This is useful for:
- Setting up development tools
- Displaying helpful information
- Configuring IDE integration
- Setting up pre-commit hooks
- Running a workflow (e.g. update script)


## Debugging Setup Hooks

When things don't work as expected, you can debug setup hooks:

### View All Hooks

In a nix-shell, inspect what's been set up:

```bash
$ nix-shell '<nixpkgs>' -A your-package

# See environment variables
[nix-shell]$ env | grep -i cmake

# See defined functions
[nix-shell]$ declare -f | grep -A 5 "^cmake"

# See phase definitions
[nix-shell]$ declare -p configurePhase
```

### Trace Hook Execution

Enable verbose output:

```bash
$ nix-build --verbose your-package.nix
```

Or add debugging to your package:

```nix
stdenv.mkDerivation {
  pname = "example";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ cmake ];

  preConfigure = ''
    echo "=== Environment at configure time ==="
    echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
    echo "NIXPKGS_CMAKE_PREFIX_PATH: $NIXPKGS_CMAKE_PREFIX_PATH"
    echo "cmakeFlags: $cmakeFlags"
  '';
}
```

## Further Reading

For more detailed documentation on specific build systems in nixpkgs:

- **Setup Hooks**: [Nixpkgs Manual - Setup Hooks](https://nixos.org/manual/nixpkgs/stable/#ssec-setup-hooks)

The nixpkgs repository also contains many examples of setup hooks in:
```
nixpkgs/pkgs/build-support/setup-hooks/
```

## Summary

Setup hooks are a powerful mechanism that allows build tools to seamlessly integrate
with `stdenv.mkDerivation`:

1. **Automatic integration**: Adding a tool to `nativeBuildInputs` automatically activates its hook
2. **Environment configuration**: Hooks set up variables, paths, and tool-specific settings
3. **Phase modification**: Hooks can customize how configure, build, and install work
4. **Reusability**: Write a hook once, use it across many packages
5. **Transparency**: Hooks make build system integration feel natural and idiomatic

By understanding setup hooks, you can package software using any build system while
maintaining the nix philosophy of reproducible, isolated builds.
