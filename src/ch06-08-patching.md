# Patching Packages

Software doesn't always build perfectly in nix. Sometimes you need to modify source
code before building: fixing hardcoded paths, backporting bug fixes, or applying
patches that haven't been released yet. Understanding how to patch packages is
essential for maintaining a functional nixpkgs setup.

This chapter covers the various ways to modify source code during the build process,
from simple string replacements to applying complex patch files.

## Why Patch?

Common scenarios where patching is necessary:

1. **Unreleased fixes**: A critical bug has been fixed upstream, but no release includes it yet
2. **Hardcoded paths**: The software assumes files are in `/usr` or `/bin`
3. **Nix-specific changes**: Adjustments needed for nix's isolated build environment
4. **Compatibility**: Changes needed for newer or older dependencies
5. **Backports**: Applying fixes from newer versions to older, stable versions

The goal is always the same: modify the source code in a reproducible way that can
be tracked and maintained.

## Small Changes: substituteInPlace

For simple string replacements, use `substituteInPlace`. This is part of stdenv
and performs in-place search-and-replace operations.

### Basic Example

```nix
{ stdenv, curl, python3 }:

stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0";
  src = ./.;

  postPatch = ''
    # Fix hardcoded path to curl
    substituteInPlace src/download.sh \
      --replace-fail '/usr/bin/curl' '${curl}/bin/curl'

    # Fix Python shebang
    substituteInPlace scripts/helper.py \
      --replace-fail '/usr/bin/python' '${python3}/bin/python'
  '';
}
```

### Multiple Replacements

You can chain multiple replacements in a single call:

```nix
postPatch = ''
  substituteInPlace config.mk \
    --replace-fail '/usr' "$out" \
    --replace-fail '/bin/bash' '${bash}/bin/bash' \
    --replace-fail 'CC = gcc' 'CC = ${stdenv.cc}/bin/gcc'
'';
```

### Common Patterns

#### Fixing Hardcoded Install Paths

```nix
postPatch = ''
  substituteInPlace Makefile \
    --replace 'PREFIX = /usr/local' 'PREFIX = ${placeholder "out"}'
'';
```

The `placeholder` function generates the output path reference that gets resolved
during the build.

#### Updating Configuration Paths

```nix
postPatch = ''
  substituteInPlace src/config.h \
    --replace '/etc/myapp' "$out/etc/myapp" \
    --replace '/var/lib/myapp' "/var/lib/myapp"  # Keep system paths
'';
```

### replaceVars: Template Substitution

For more complex substitutions involving multiple variables, use `replaceVars`. This
function processes template files and replaces `@variable@` patterns with their
corresponding values, with built-in safety checks to ensure all variables are replaced.

```nix
{ stdenv, replaceVars, python3, curl }:

stdenv.mkDerivation {
  pname = "my-app";
  version = "1.0";
  src = ./.;

  # Create a patched config file from a template
  postInstall = ''
    mkdir -p $out/etc
    cp ${replaceVars ./config.template {
      python = "${python3}/bin/python";
      curl = "${curl}/bin/curl";
      prefix = placeholder "out";
    }} $out/etc/config.conf
  '';
}
```

The template file `config.template` might look like:

```
python_path = @python@
curl_path = @curl@
install_prefix = @prefix@
```

Each `@variable@` gets replaced with the corresponding attribute value.

**Advantages over substituteInPlace:**
- **Type safety**: Fails if variables in the template lack matching replacements
- **Detection**: Catches leftover unmatched `@variable@` patterns
- **Cleaner**: Keeps templates separate from nix code
- **Explicit**: Use `null` to deliberately skip certain variables

### Example: Patching Python Module to Use Nix Store Paths

A common scenario is patching Python modules that execute external programs. Python
code often expects tools to be in system paths, but in nix they're in the store.

Consider a Python module that calls `git` and `ssh`:

```python
# mymodule/vcs.py
import subprocess

def clone_repo(url):
    # This assumes git is in PATH
    subprocess.run(['git', 'clone', url])

def ssh_command(host, cmd):
    # This assumes ssh is in PATH
    subprocess.run(['ssh', host, cmd])
```

In nix, we need to patch these to use full store paths:

```nix
{ lib
, python3Packages
, git
, openssh
, replaceVars
}:

python3Packages.buildPythonPackage {
  pname = "mymodule";
  version = "1.0";
  src = ./.;

  postPatch = ''
    # Patch the Python code to use nix store paths
    substituteInPlace mymodule/vcs.py \
      --replace-fail "['git'" "['${git}/bin/git'" \
      --replace-fail "['ssh'" "['${openssh}/bin/ssh'"
  '';

  meta = with lib; {
    description = "VCS utilities with patched binary paths";
    license = licenses.mit;
  };
}
```

This pattern is essential for Python packages that shell out to system utilities,
ensuring they work correctly as we cannot guarantee what will be on PATH when the
script is being ran.

## Large Changes: The patches Attribute

For substantial modifications, use actual patch files. These are typically generated
with `git diff` or `diff -u` and applied during the `patchPhase`.

### Basic Patch Application

```nix
{ stdenv, fetchurl, fetchpatch }:

stdenv.mkDerivation {
  pname = "example";
  version = "1.0";

  src = fetchurl {
    url = "https://example.com/example-1.0.tar.gz";
    sha256 = "...";
  };

  patches = [
    # Apply a local patch file
    ./fix-build-error.patch

    # Fetch a patch from upstream
    (fetchpatch {
      url = "https://github.com/example/example/commit/abc123.patch";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    })
  ];
}
```

### Creating Patch Files

Generate patches from a package source:

```bash
nix-shell -A <pkg> # Create a nix shell which can perform the build
$ unpackPhase
$ cd $sourceRoot

$ git init . # Create a git repo, so we can generate a diff
$ git add .
$ git commit -m "init"

$ configurePhase # Get to the point in the build in which it fails
$ buildPhase

# Make changes to the code until build succeeds, then generate patch:
$ git diff > ../fix-build-error.patch # Then move the patch to the package dir
```

### Patch File Best Practices

Place patches in the same directory as your nix expression:

```
pkgs/example/
├── default.nix
├── fix-build-error.patch
├── backport-security-fix.patch
└── nix-compat.patch
```

If you have many patches, it may be good to prefix the patches with a number to
designate the order in which they should be applied. E.g. 0001-first.patch. Lists
in Nix will preserve the order in which they were listed, but the numbered prefix
is a good signal to other contributors that the order was intentional.

#### Document Your Patches

Always add comments explaining why patches exist:

```nix
patches = [
  # Fix build error with GCC 13
  # Upstream PR: https://github.com/example/example/pull/123
  # Remove when version > 1.0
  ./fix-build-error.patch

  # Backport security fix for CVE-2024-12345
  # Upstream commit: https://github.com/example/example/commit/abc123
  # Remove when version >= 1.1
  (fetchpatch {
    url = "https://github.com/example/example/commit/abc123.patch";
    sha256 = "sha256-...";
  })

  # Nix-specific: Fix hardcoded /usr paths
  # This will always be needed
  ./nix-compat.patch
];
```

Good comments include:
- **Why** the patch is needed
- **Where** it came from (upstream PR/commit)
- **When** it can be removed (version number or condition)

## Using fetchpatch

`fetchpatch` is the preferred way to fetch patches from the internet. It automatically
sanitizes and normalizes patches for better reproducibility.

### Basic Usage

```nix
{ fetchpatch }:

# In your derivation:
patches = [
  (fetchpatch {
    url = "https://github.com/user/repo/commit/abc123.patch";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  })
];
```

### Getting the Hash

You can attempt to use `nix-prefetch-url` to get the hash:

```bash
$ nix-prefetch-url https://github.com/user/repo/commit/abc123.patch
sha256-RealHashWillBeShownHere
```

However, `fetchpatch` performs its own sanitization, so the hash from
`nix-prefetch-url` often won't match. Instead, use a fake hash first:

```nix
(fetchpatch {
  url = "https://github.com/user/repo/commit/abc123.patch";
  sha256 = lib.fakeHash;  # or "sha256-AAAA..."
})
```

Build and the error will show the correct hash:

```
error: hash mismatch in fixed-output derivation
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  got:       sha256-RealHashForFetchpatchOutput=
```

Copy the "got" hash to your expression.

### Why fetchpatch Hashes Differ

`fetchpatch` performs several normalizations:
- Strips timestamps from patch headers
- Normalizes line endings
- Removes trailing whitespace
- Sorts git index lines
- `fetchpatch` also allows for explicit includsion or exclusion of files.

This makes patches more stable across different git versions and patch formats,
but means the hash differs from the raw file hash.

### Excluding Files from Patches

Sometimes patches include unwanted changes (like test data or generated files):

```nix
(fetchpatch {
  url = "https://github.com/user/repo/commit/abc123.patch";
  sha256 = "sha256-...";
  excludes = [
    "tests/fixtures/*"
    "*.png"
  ];
})
```

### Including Only Specific Files

Conversely, you can extract only certain changes:

```nix
(fetchpatch {
  url = "https://github.com/user/repo/commit/abc123.patch";
  sha256 = "sha256-...";
  includes = [
    "src/*.c"
    "include/*.h"
  ];
})
```

### Relative Paths in Patches

If a patch's paths don't match your source tree:

```nix
(fetchpatch {
  url = "https://github.com/user/repo/commit/abc123.patch";
  sha256 = "sha256-...";
  stripLen = 1;  # Remove one directory level from paths
})
```

This is useful when a patch is generated from a subdirectory or monorepo.

## Complex Example: Multiple Patches

Here's a realistic example combining different patching techniques:

```nix
{ lib
, stdenv
, fetchFromGitHub
, fetchpatch
, cmake
, openssl
, zlib
}:

stdenv.mkDerivation rec {
  pname = "example-app";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "app";
    rev = "v${version}";
    sha256 = "sha256-...";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ openssl zlib ];

  patches = [
    # Fix build with OpenSSL 3.0
    # Upstream PR: https://github.com/example/app/pull/456
    # Remove when version > 2.1.0
    (fetchpatch {
      name = "openssl-3-compat.patch";
      url = "https://github.com/example/app/pull/456.patch";
      sha256 = "sha256-...";
    })

    # Backport crash fix from main branch
    # Upstream commit: https://github.com/example/app/commit/def789
    # Remove when version >= 2.2.0
    (fetchpatch {
      name = "fix-crash-on-invalid-input.patch";
      url = "https://github.com/example/app/commit/def789.patch";
      sha256 = "sha256-...";
      # Only include the actual fix, not test changes
      includes = [ "src/*.cpp" "include/*.h" ];
    })

    # Nix-specific: Fix hardcoded paths
    # This patch will always be needed
    ./fix-hardcoded-paths.patch
  ];

  postPatch = ''
    # Additional small fixes
    substituteInPlace CMakeLists.txt \
      --replace '/usr/share' "$out/share"

    # Update version file
    echo "${version}" > VERSION

    # Fix test data paths
    substituteInPlace tests/test_config.cpp \
      --replace '../testdata' "$PWD/testdata"
  '';

  meta = with lib; {
    description = "Example application with multiple patches";
    homepage = "https://github.com/example/app";
    license = licenses.mit;
  };
}
```

## Binary Patching: patchelf and autoPatchelfHook

Sometimes you need to patch compiled binaries, especially when dealing with
proprietary software or pre-built binaries. The `patchelf` tool modifies
ELF (Linux) binaries.

### Manual Binary Patching

```nix
{ stdenv, patchelf, lib }:

stdenv.mkDerivation {
  pname = "proprietary-app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ patchelf ];

  installPhase = ''
    mkdir -p $out/bin
    cp app $out/bin/

    # Set the interpreter (dynamic linker)
    patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
      $out/bin/app

    # Set RPATH so the app can find shared libraries
    patchelf --set-rpath ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} \
      $out/bin/app
  '';
}
```

### Using autoPatchelfHook

For applications with many binaries and libraries, `autoPatchelfHook` automatically
handles patching:

```nix
{ stdenv, autoPatchelfHook, openssl, zlib }:

stdenv.mkDerivation {
  pname = "binary-app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ autoPatchelfHook ];

  # Specify runtime dependencies
  buildInputs = [ openssl zlib ];

  installPhase = ''
    mkdir -p $out/{bin,lib}
    cp -r bin/* $out/bin/
    cp -r lib/* $out/lib/
    # autoPatchelfHook runs automatically after install
  '';
}
```

The hook:
1. Finds all ELF binaries
2. Sets the correct interpreter
3. Fixes RPATH to find dependencies
4. Reports missing dependencies

### Debugging autoPatchelfHook

If autoPatchelfHook reports missing libraries:

```nix
buildInputs = [ openssl zlib ];

# Add missing dependencies
runtimeDependencies = [
  # Additional libraries needed at runtime
  # These are added to RPATH, generally runtimeDependencies is needed for dlopen calls
  someOtherLib
];

# Or for system libraries
autoPatchelfIgnoreMissingDeps = [
  # Libraries that are okay to be missing, provided impurely
  "libGL.so.1"
];
```

### When to Use Binary Patching

Use `patchelf` and `autoPatchelfHook` when:
- Packaging pre-compiled binaries
- Dealing with proprietary software
- Building from binary releases (AppImages, .deb packages, etc.)
- Dynamic libraries have wrong RPATH

For source-based builds, prefer source patches over binary patching.

## Patch Application Order

Understanding the order of operations helps debug patching issues:

1. **unpackPhase**: Extract the source
2. **patchPhase**: Apply patches from `patches` attribute
3. **postPatch**: Runhook ran after patches (ideal for `substituteInPlace`)
4. **configurePhase**: Run build system configuration
5. ...rest of build

If patches fail, check:
- Patch paths match the source tree structure
- Patches apply cleanly (no conflicts)
- The source version matches what the patch expects

## Best Practices

1. **Prefer source patches over binary patches** - More maintainable and transparent
2. **Document why patches exist** - Future maintainers need context
3. **Include removal conditions** - Specify when patches can be removed
4. **Use fetchpatch for upstream patches** - Better reproducibility
5. **Keep patches minimal** - Only change what's necessary
6. **Test patch removal regularly** - Don't keep stale patches
7. **Upstream your patches** - Contribute fixes back to projects

## Common Pitfalls

### Forgetting to Update After Upstream Changes

When updating package versions, check if patches still apply:

```nix
# BAD: Patches for old version might not apply
version = "2.0";  # Updated, but patches still reference old code
patches = [ ./fix-for-1.0.patch ];  # This might fail!
```

Always test builds after version updates.

### Patching Generated Files

Don't patch files that get regenerated:

```nix
# BAD: configure is regenerated by autoreconf
patches = [ ./fix-configure.patch ];

# GOOD: Patch the source and regenerate
patches = [ ./fix-configure.ac.patch ];
nativeBuildInputs = [ autoreconfHook ];
```

## Summary

Patching in nix provides powerful tools for modifying source code:

1. **substituteInPlace**: Quick string replacements in source files
2. **patches attribute**: Apply patch files during patchPhase
3. **fetchpatch**: Fetch and normalize patches from the internet
4. **patchelf/autoPatchelfHook**: Modify compiled binaries
5. **Documentation**: Always explain why patches exist and when to remove them

The key is choosing the right tool:
- Small changes → `substituteInPlace`
- Large changes → patch files
- Binary modifications → `autoPatchelfHook`

Well-maintained patches make packages reliable and easy to update, while good
documentation ensures the changes remain understandable over time.
