# Stdenv

`stdenv` provides a foundation for building C/C++ software with nixpkgs. It includes, but is not limited to
containing tools such as: a C compiler and related tools, GNU coreutils, GNU awk, GNU sed, findutils, strip, bash, GNUmake, bzip2, gzip,
and many more tools. Stdenv also provides a default "builder.sh" script which will perform the build of a package. The default builder script
is comprised of many smaller "phases" which package maintainers can alter slightly as needed. The goal of `stdenv` is to enable most C/C++ + `Makefile` workflows; in theory, if a software
package has these installation steps:
```
./configure # configurePhase, optional
make # buildPhase
make install # installPhase
```
Then the only necessary changes for it to work with `stdenv.mkDerivation` would be the inclusion of
`installFlags = [ "PREFIX=$(out)" ];` to communicate where the package should be installed with nix.

## Unique qualities of Nixpkgs' Stdenv

### Wrapped C Compiler

The C compiler accessible through `stdenv.cc` is not the raw compiler binary—it's a shell script wrapper. This wrapper is one of the most important features of the Nix build system and handles several critical tasks that would otherwise require manual configuration.

#### Why the wrapper exists

Traditional Linux distributions rely on hardcoded system paths:
- Headers in `/usr/include`
- Libraries in `/usr/lib` and `/lib`
- The C library and dynamic linker at known system locations

NixOS cannot use these conventions because:
1. **Isolation**: Each package lives in its own `/nix/store/<hash>-name` directory
2. **Reproducibility**: Dependencies must be explicitly declared, not implicitly found
3. **Multiple versions**: Different package versions coexist without conflicts
4. **No global state**: There is no `/usr` to rely on

Without the wrapper, you would need to manually specify include and library paths for every dependency in every package. The wrapper automates this by translating your `buildInputs` declarations into the appropriate compiler and linker flags.

#### What the wrapper does

The compiler wrapper (implemented in `pkgs/build-support/cc-wrapper/`) performs several automatic transformations:

**Include path management:**
- Scans each package in `buildInputs` for `include/` directories
- Automatically adds `-isystem` flags pointing to those directories
- Handles compiler-specific includes (e.g., GCC's `include-fixed`)
- On macOS, adds framework paths using `-iframework`

**Library path configuration:**
- Adds `-L` flags for library search paths from dependencies
- Configures `RPATH` using `-rpath` so binaries can find their dependencies at runtime
- Sets `-B` flags for compiler auxiliary executables
- Ensures executables don't need `LD_LIBRARY_PATH` to find libraries

**Security hardening flags:**
The wrapper automatically enables several security features (unless explicitly disabled):

- `fortify` / `fortify3`: Memory corruption protection (`-D_FORTIFY_SOURCE=2` or `=3`)
- `stackprotector`: Stack smashing detection (`-fstack-protector-strong`)
- `pic`: Position-independent code (`-fPIC`)
- `format`: Format string protection (`-Wformat -Werror=format-security`)
- `strictoverflow`: Overflow behavior control
- `trivialautovarinit`: Auto-variable initialization to detect uninitialized memory
- Additional hardening on supported platforms (stack clash protection, control flow integrity, etc.)

To disable specific hardening features:
```nix
stdenv.mkDerivation {
  pname = "example";
  version = "1.0";

  hardeningDisable = [ "fortify" "stackprotector" ];
}
```

**Cross-compilation support:**
The wrapper handles different platform types through a role-based system:
- **Build platform**: Where compilation happens
- **Host platform**: Where the built code will run
- **Target platform**: What platform a compiler generates code for (for compilers themselves)

This allows the same wrapper infrastructure to work for native builds and cross-compilation.

#### Key environment variables

The wrapper uses several environment variables to communicate with the compiler:

**NIX_CFLAGS_COMPILE**:
Compiler flags automatically prepended to every compilation command. Populated with `-isystem` flags for include directories.

```bash
# Example value:
NIX_CFLAGS_COMPILE="-isystem /nix/store/...-zlib-1.2.11-dev/include -isystem /nix/store/...-openssl-3.0.0-dev/include"
```

**Note:** `-isystem` works similarly to tradtiional `-I` argument, but the paths are appended rather than prepended to the search path.

Platform-specific variants exist for cross-compilation:
- `NIX_CFLAGS_COMPILE_FOR_BUILD`: Build platform
- `NIX_CFLAGS_COMPILE`: Host platform (default)
- `NIX_CFLAGS_COMPILE_FOR_TARGET`: Target platform

**NIX_LDFLAGS**:
Linker flags for finding libraries and setting runtime paths.

```bash
# Example value:
NIX_LDFLAGS="-L/nix/store/...-zlib-1.2.11/lib -rpath /nix/store/...-zlib-1.2.11/lib"
```

**NIX_HARDENING_ENABLE**:
Space-separated list of enabled hardening features.

```bash
# Default value:
NIX_HARDENING_ENABLE="fortify stackprotector pic strictoverflow format"
```

#### How dependencies are discovered

The cc-wrapper's setup hook (`pkgs/build-support/cc-wrapper/setup-hook.sh`) registers a function that runs for each package in `buildInputs`:

```bash
ccWrapper_addCVars() {
  if [ -d "$1/include" ]; then
    export NIX_CFLAGS_COMPILE+=" -isystem $1/include"
  fi
  if [ -d "$1/Library/Frameworks" ]; then  # macOS
    export NIX_CFLAGS_COMPILE+=" -iframework $1/Library/Frameworks"
  fi
}
```

This automatic discovery is why you can simply add `openssl` to `buildInputs` and the compiler will find `openssl.h` without any manual configuration.

#### Debugging the wrapper

Set `NIX_DEBUG=1` to see what the wrapper is doing:

```bash
$ NIX_DEBUG=1 $CC -v myfile.c
```

This reveals:
- All hardening flags being applied
- Extra compiler flags from `NIX_CFLAGS_COMPILE`
- The actual underlying compiler command
- How paths are being added

You can also inspect the wrapper script directly:

```bash
$ cat $(which gcc)
# Shows the wrapper shell script
```

#### When to use the unwrapped compiler

In rare cases, you need access to the unwrapped compiler:

```nix
{ stdenv }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";

  # Access unwrapped GCC, highly discouraged
  nativeBuildInputs = [ stdenv.cc.cc ];

  # Or unwrapped binutils
  buildInputs = [ stdenv.cc.bintools.bintools ];
}
```

In general, you wlil not need to use the unwrapped compiler, however you may need to when:
- Building a new compiler toolchain
- Creating custom wrapper configurations
- Implementing bare-metal cross-compilation where you need precise control
- The automatic path management conflicts with your build system

For normal package builds, always use the wrapped compiler (`stdenv.cc`).

### Stdenv Shell Functions

Stdenv provides a comprehensive collection of bash functions in its setup script (`pkgs/stdenv/generic/setup.sh`). These functions handle common packaging tasks and are available in all phases of a build.

#### Text Substitution Functions

##### substituteInPlace

Performs in-place text replacements in files. This is one of the most frequently used functions for fixing hardcoded paths and updating configuration.

**Replacement options:**
- `--replace <old> <new>`: Replace all occurrences
- `--replace-warn <old> <new>`: Same but warns if no matches found
- `--replace-fail <old> <new>`: Fails if no matches found (recommended for critical replacements)
- `--subst-var <varname>`: Replace `@varname@` with environment variable value
- `--subst-var-by <varname> <value>`: Replace `@varname@` with specific value

**Usage:**
```nix
postPatch = ''
  # Fix hardcoded paths
  substituteInPlace Makefile \
    --replace-fail "/usr/bin" "$out/bin" \
    --replace-fail "/etc" "$out/etc"

  # Substitute variables
  substituteInPlace config.h \
    --subst-var-by VERSION "$version" \
    --subst-var prefix
'';
```

**Common use cases:**
- Replacing hardcoded system paths (`/usr`, `/bin`, `/etc`)
- Updating version strings in source files
- Fixing paths in build scripts and Makefiles
- Customizing configuration templates

For more complex patching scenarios, see the [patching chapter](./ch06-08-patching.md#small-changes-substituteinplace).

##### substitute

Creates a new file with substituted content without modifying the original.

**Usage:**
```nix
buildPhase = ''
  substitute config.template config.out \
    --replace "@PREFIX@" "$out" \
    --replace "@VERSION@" "$version"
'';
```

Use this when you need to preserve the original file or generate multiple variants from a template.

##### substituteAll / substituteAllInPlace

Automatically replaces all `@varname@` patterns that match environment variables.

**Usage:**
```nix
postInstall = ''
  # Replace all @VAR@ patterns with environment variable values
  substituteAll config.template $out/etc/config
'';
```

**Behavior:**
- Only substitutes variables that exist in the environment
- Skips variables starting with uppercase or underscore (prevents accidental global variable substitution)
- Undefined `@varname@` patterns remain in the output

#### Script Patching

##### patchShebangs

Modifies script shebangs to use Nix store paths instead of system paths. This is critical for making scripts work in the Nix environment.

**Parameters:** `[--build | --host] PATH...`

**Transformations:**
```bash
# Before:
#!/bin/sh
#!/usr/bin/env python
#!/usr/bin/python3

# After:
#!/nix/store/<hash>-bash/bin/sh
#!/nix/store/<hash>-python3/bin/python
#!/nix/store/<hash>-python3/bin/python3
```

**Flags:**
- `--build`: Resolve commands from build-time dependencies (for build scripts)
- `--host`: Resolve commands from runtime dependencies (default, for installed programs)

**Usage:**
```nix
postInstall = ''
  # Automatically run by fixupPhase, but can be called manually:
  patchShebangs --host $out/bin
  patchShebangs --build scripts/
'';
```

**When it runs automatically:**
The `fixupPhase` automatically calls `patchShebangs --host` on all outputs. Disable with `dontPatchShebangs = true`.

**Important notes:**
- Only processes files marked as executable
- Skips scripts already pointing to valid Nix store paths
- Cannot patch shebangs in files that aren't executable

#### Path Manipulation

##### addToSearchPath

Adds a directory to a colon-separated search path variable.

**Usage:**
```bash
addToSearchPath PATH "$pkg/bin"
addToSearchPath PKG_CONFIG_PATH "$pkg/lib/pkgconfig"
addToSearchPath XDG_DATA_DIRS "$pkg/share"
```

This is commonly used in setup hooks to extend environment variables as packages are processed.

##### prependToVar / appendToVar

Helpers for manipulating bash variables and avoiding common bash pitfalls. Adds elements to the beginning or end of a variable (handles both arrays and strings).

**Usage:**
```nix
preConfigure = ''
  prependToVar configureFlags "--disable-dependency-tracking"
  appendToVar makeFlags "PREFIX=$out"
'';
```

These are useful when you need to modify build variables in phase hooks.

##### stripHash

Removes the Nix store hash prefix from a path or filename.

**Usage:**
```bash
name=$(stripHash "/nix/store/abc123...-package-1.0")
# Returns: "package-1.0"
```

Useful for extracting package names from store paths.

#### Multiple Output Functions

##### moveToOutput

Relocates files from one output to another. Essential for packages using multiple outputs to reduce closure size.

**Parameters:** `moveToOutput <pattern> <destination_output>`

**Usage:**
```nix
stdenv.mkDerivation {
  outputs = [ "out" "dev" "doc" ];

  postInstall = ''
    # Move headers to dev output
    moveToOutput "include" "$dev"

    # Move documentation to doc output
    moveToOutput "share/doc" "$doc"
    moveToOutput "share/man" "$doc"

    # Move static libraries to dev
    moveToOutput "lib/*.a" "$dev"
  '';
}
```

**Behavior:**
- Moves matching files/directories from `$out` to the specified output
- Handles both files and symlinks correctly
- Removes empty parent directories after moving
- Use `REMOVE` as destination to delete files instead

For more details on multiple outputs, see the [multiple outputs chapter](./ch06-09-multiple-outputs.md).

#### Hook Management

##### runHook

Executes all registered hooks with a specified name in sequence.

**Usage:**
```bash
runHook preInstall
# ... installation logic ...
runHook postInstall
```

Standard hook points include:
- `preConfigure` / `postConfigure`
- `preBuild` / `postBuild`
- `preInstall` / `postInstall`
- `preFixup` / `postFixup`

You can define custom hooks:
```nix
preInstall = ''
  echo "Running custom pre-install logic"
  mkdir -p $out/custom
'';
```

#### Other Utility Functions

##### dumpVars

Exports environment variables to `env-vars` file for debugging failed builds. Automatically called on build failure (disable with `noDumpEnvVars=1`).

##### echoCmd

Prints commands with proper escaping for debugging:

```bash
echoCmd 'configure flags' "${flagsArray[@]}"
```

### Further Reading

For a complete reference of all stdenv functions, see:
- [Nixpkgs Manual - Stdenv Functions](https://nixos.org/manual/nixpkgs/stable/#ssec-stdenv-functions)
- [Nix Pills - Basic Dependencies and Hooks](https://nixos.org/guides/nix-pills/20-basic-dependencies-and-hooks)

The stdenv setup script source code is also highly readable:
- Main setup: `pkgs/stdenv/generic/setup.sh`
- Compiler wrapper: `pkgs/build-support/cc-wrapper/setup-hook.sh`
- Multiple outputs: `pkgs/build-support/setup-hooks/multiple-outputs.sh`
