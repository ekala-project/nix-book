# Runtime Dependencies

While [build dependencies](./ch06-04-build-dependencies.md) are needed to compile software,
runtime dependencies are the libraries and programs that must be available when
the software actually runs. In traditional package managers, these are often tracked
separately through complex metadata. Nix takes a simpler approach: it automatically
detects runtime dependencies by scanning the built artifacts for references to the nix store.

This chapter explains how nix identifies runtime dependencies, how to inspect them,
and how to ensure programs can find their dependencies at runtime.

## What Are Runtime Dependencies?

Runtime dependencies are any build inputs that remain referenced in the final
installed output. When you build a package, nix scans the output files looking
for references to store paths. Any store path found becomes a runtime dependency.

For example, when compiling a C program that links against OpenSSL:

```nix
{ stdenv, openssl }:

stdenv.mkDerivation {
  pname = "myapp";
  version = "1.0";
  src = ./.;

  buildInputs = [ openssl ];

  buildPhase = ''
    $CC main.c -o myapp -lssl -lcrypto
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp myapp $out/bin/
  '';
}
```

The compiled binary `myapp` will contain hardcoded paths to OpenSSL's shared libraries:

```bash
$ ldd /nix/store/xxx-myapp/bin/myapp
    libssl.so.3 => /nix/store/yyy-openssl/lib/libssl.so.3
    libcrypto.so.3 => /nix/store/yyy-openssl/lib/libcrypto.so.3
    libc.so.6 => /nix/store/zzz-glibc/lib/libc.so.6
```

Because these store paths appear in the binary, nix knows OpenSSL and glibc
are runtime dependencies.

## How Nix Detects Runtime Dependencies

Nix uses a straightforward but effective method to detect runtime dependencies:
it scans the output files for strings that look like nix store paths.

Specifically, nix looks for the hash portion of store paths. A store path has the format:
```
/nix/store/<32-character-hash>-<name>
```

During the build completes, nix scans all files in each output for any
occurrence of the 32-character hash of dependencies that were available during the build.
If found, that dependency is marked as a runtime dependency of the output.

This works because:
1. Compiled binaries contain full paths to shared libraries
2. Scripts often have shebangs like `#!/nix/store/xxx-bash/bin/bash`
3. Configuration files may reference other programs by full path
4. Any file that embeds a store path will cause that path to be retained

**Note:** Certain formats such as `.jar` files are compressed, and the naive
dependency scanning will not be able to decompress the contents to search for
retained dependencies. In this case, needed dependencies will need to be added
through other means; the most common of which is to create a file in 
`<output>/nix-support/<any file name>` with the paths needed.

### The Runtime Closure

The complete set of runtime dependencies, including transitive dependencies
(dependencies of dependencies), is called the "runtime closure" or just "closure".

For instance, if your program depends on OpenSSL, and OpenSSL depends on zlib,
then your program's closure includes both OpenSSL and zlib, even though your
program never directly references zlib.

## Inspecting Runtime Dependencies

Nix provides several commands to inspect runtime dependencies:

### Immediate Dependencies

To see direct runtime dependencies of a package:

```bash
$ nix-store -q --references /nix/store/xxx-myapp
/nix/store/yyy-openssl
/nix/store/zzz-glibc
/nix/store/aaa-gcc-libs
```

This shows only the packages that are directly referenced in the output.

### Complete Closure

To see all runtime dependencies, including transitive ones:

```bash
$ nix-store -q --requisites /nix/store/xxx-myapp
/nix/store/yyy-openssl
/nix/store/zzz-glibc
/nix/store/aaa-gcc-libs
/nix/store/bbb-zlib
/nix/store/ccc-linux-headers
...
```

This lists every package in the runtime closure.

### Closure Size

To see how much disk space the closure requires:

```bash
$ nix path-info -Sh /nix/store/xxx-myapp
/nix/store/xxx-myapp    256.3M
```

Understanding closure size is important because:
- It affects download time when using binary caches
- It determines disk usage for deployed systems
- Smaller closures mean faster container images and updates

### Dependency Tree

To visualize the dependency tree:

```bash
$ nix-store -q --tree /nix/store/xxx-myapp
/nix/store/xxx-myapp
├───/nix/store/yyy-openssl
│   ├───/nix/store/bbb-zlib
│   │   └───/nix/store/zzz-glibc
│   │       └───...
│   └───/nix/store/zzz-glibc
│       └───...
└───/nix/store/zzz-glibc
    └───...
```

The [nix-tree](https://github.com/utdemir/nix-tree) tool is a TUI which is
immensely helpful in finding dependencies in a closure.

### Finding Why a Package Is in the Closure

To find out why a specific package is in your closure:

```bash
$ nix why-depends /nix/store/xxx-myapp /nix/store/bbb-zlib
/nix/store/xxx-myapp
└───/nix/store/yyy-openssl: …/openssl/lib/libssl.so.3
    └───/nix/store/bbb-zlib: …/zlib/lib/libz.so.1
```

This shows the dependency chain that causes zlib to be included.

**Note:** The `--precise` argument will also tell you which file and where in
the file it found the reference, this is useful for pinpoint how the reference
was retained.

## Making Runtime Dependencies Available

Sometimes dependencies need to be available on `PATH` or through environment
variables when a program runs. This is common for programs that execute other
programs, or for interpreted languages.

### The Problem

Consider a shell script that uses common utilities:

```bash
#!/usr/bin/env bash
# myscript.sh

grep "pattern" file.txt | sed 's/old/new/' | sort
```

This script assumes `grep`, `sed`, and `sort` are available on `PATH`. But in nix,
programs don't have access to a global `PATH`. They need to be explicitly provided.

### Solution: wrapProgram

Nix provides `wrapProgram` (from `makeWrapper`) to solve this. It creates a wrapper
script that sets up the environment before executing the actual program.

```nix
{ stdenv, lib, makeWrapper, gnugrep, gnused, coreutils }:

stdenv.mkDerivation {
  pname = "myscript";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp myscript.sh $out/bin/myscript

    # Wrap the script to provide dependencies on PATH
    wrapProgram $out/bin/myscript \
      --prefix PATH : ${lib.makeBinPath [ gnugrep gnused coreutils ]}
  '';
}
```

Now when `myscript` runs, the wrapper automatically adds `grep`, `sed`, and `sort` to `PATH`.

TODO: link to dedicated `wrapProgram` page.

### Example: Python Script with Dependencies

A Python script that imports external modules:

```nix
{ stdenv, makeWrapper, python3, python3Packages }:

stdenv.mkDerivation {
  pname = "my-python-tool";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ python3 ];

  installPhase = ''
    mkdir -p $out/bin
    cp tool.py $out/bin/my-python-tool

    wrapProgram $out/bin/my-python-tool \
      --prefix PYTHONPATH : "${python3Packages.requests}/${python3.sitePackages}" \
      --prefix PYTHONPATH : "${python3Packages.click}/${python3.sitePackages}"
  '';
}
```

Now the Python script can import `requests` and `click` at runtime.

**Note**: For Python packages, it's better to use `python3Packages.buildPythonApplication`
or `buildPythonPackage`, which handle this automatically. Many mkDerivation helpers
which automatically wrap programs will generally also support `makeWrapperArgs`
which allows you to add more args outside of the defaults.

### Example: Application Needing Qt Plugins

Qt applications need to find their plugins at runtime:

```nix
{ stdenv, qt5, makeWrapper }:

stdenv.mkDerivation {
  pname = "qt-app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper qt5.wrapQtAppsHook ];
  buildInputs = [ qt5.qtbase ];

  # wrapQtAppsHook automatically wraps Qt apps in postFixup
  # But if you need manual control:
  postInstall = ''
    wrapProgram $out/bin/qt-app \
      --prefix QT_PLUGIN_PATH : "${qt5.qtbase.bin}/${qt5.qtbase.qtPluginPrefix}"
  '';
}
```

The `wrapQtAppsHook` handles this automatically for most cases.

## Ensuring Hidden Dependencies Are Retained

Sometimes a dependency is needed at runtime but won't be automatically detected
because it's not referenced in the output files. Common cases include:

### Plugins Loaded Dynamically

If your program loads plugins by name at runtime, nix won't detect them:

```c
// main.c - won't reference libplugin.so in source
void *handle = dlopen("libplugin.so", RTLD_LAZY);
```

In this case, try using `autoPatchelfHook` and reference the libraries as
`runtimeDependencies` which will attempt to add the necessary `DT_RUNPATH` entries
which will point to the library location.

### Compressed Archives

JAR files, ZIP archives, or other compressed formats may contain references
to store paths, but nix's scanner will not attempt to decompress them to search
for references.

### Solution: Explicit Runtime Dependencies

You can force nix to retain dependencies by writing references to `$out/nix-support`:

```nix
{ stdenv, plugin1, plugin2, jdk }:

stdenv.mkDerivation {
  pname = "app-with-plugins";
  version = "1.0";
  src = ./.;

  buildInputs = [ plugin1 plugin2 jdk ];

  installPhase = ''
    mkdir -p $out/bin
    cp app.jar $out/bin/

    # Ensure plugins are retained in closure
    mkdir -p $out/nix-support
    echo ${plugin1} >> $out/nix-support/propagated-user-env-packages
    echo ${plugin2} >> $out/nix-support/propagated-user-env-packages

    # Or just create a reference anywhere in $out:
    echo "Plugins: ${plugin1} ${plugin2}" > $out/nix-support/plugins.txt
  '';
}
```

By writing the store paths to any file in `$out`, nix's scanner will find them
and include those packages in the runtime closure.

## Patching for Runtime Dependencies

Some programs hardcode paths that need to be fixed to work with nix. This is
especially common with:
- Scripts with hardcoded shebangs
- Programs looking for libraries in `/lib` or `/usr/lib`
- Python/Ruby/Perl scripts importing system modules

### Patching Shebangs

Nix automatically patches shebangs during `fixupPhase`:

```bash
# Before:
#!/usr/bin/python3

# After:
#!/nix/store/xxx-python3/bin/python3
```

This happens automatically for any file with execute permissions.

### Patching Hardcoded Paths

For programs that hardcode system paths:

```nix
{ stdenv, substituteAll, python3, curl }:

stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0";
  src = ./.;

  buildInputs = [ python3 curl ];

  postPatch = ''
    # Fix hardcoded paths in source
    substituteInPlace tool.py \
      --replace '/usr/bin/python3' '${python3}/bin/python3' \
      --replace '/usr/bin/curl' '${curl}/bin/curl'
  '';
}
```

The `substituteInPlace` function (from stdenv) performs in-place replacements.

### Python Runtime Imports

Python programs that import other modules need those modules in `PYTHONPATH`.
However, modifying `PYTHONPATH` globally isn't always reliable, especially when
the Python program executes other programs.

For Python packages, use `buildPythonPackage`:

```nix
{ python3Packages }:

python3Packages.buildPythonPackage {
  pname = "my-python-app";
  version = "1.0";
  src = ./.;

  propagatedBuildInputs = with python3Packages; [
    requests
    click
    pyyaml
  ];

  # buildPythonPackage automatically:
  # - Sets up PYTHONPATH
  # - Creates wrapper scripts
  # - Handles site-packages layout
}
```

This ensures Python can find its dependencies reliably.

### Perl and Ruby

Similar patterns apply to Perl and Ruby:

```nix
{ perlPackages }:

perlPackages.buildPerlPackage {
  pname = "my-perl-script";
  version = "1.0";
  src = ./.;

  propagatedBuildInputs = with perlPackages; [
    LWP
    JSON
  ];
}
```

## Reducing Runtime Closure Size

Large closures can be problematic for deployments. Here are strategies to reduce them:

### Use Multiple Outputs

Split development files from runtime files:

```nix
stdenv.mkDerivation {
  pname = "mylib";
  version = "1.0";
  src = ./.;

  outputs = [ "out" "dev" "doc" ];

  postInstall = ''
    # Headers go to dev
    moveToOutput "include" "$dev"

    # Docs go to doc
    moveToOutput "share/doc" "$doc"
  '';
}
```

See [the multiple outputs section](./ch06-09-multiple-outputs.md) for details.

### Avoid Unnecessary Propagation

Don't use `propagatedBuildInputs` unless necessary. It increases downstream closures.

### Use Static Linking Selectively

Static linking can reduce runtime dependencies but increases binary size and
circumvents the principle of "maximal sharing" of dependencies between packages.

### Inspect and Eliminate Unwanted References

Sometimes build artifacts accidentally reference build-time dependencies:

```bash
# Find why a build tool is in the closure
$ nix why-depends ./result /nix/store/xxx-gcc

# The culprit might be a debug symbol or metadata file
```

Use `removeReferencesTo` to strip unwanted references:

```nix
{ stdenv, removeReferencesTo, gcc }:

stdenv.mkDerivation {
  pname = "app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ removeReferencesTo ];

  postInstall = ''
    # Remove reference to gcc from the binary
    remove-references-to -t ${gcc} $out/bin/app
  '';
}
```

**Warning**: Only remove references you're certain are not needed at runtime.

## Common Runtime Dependency Patterns

### GUI Applications

Desktop applications need many runtime components:

```nix
{ stdenv, makeWrapper, gtk3, hicolor-icon-theme, shared-mime-info }:

stdenv.mkDerivation {
  pname = "gui-app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ gtk3 ];

  postInstall = ''
    wrapProgram $out/bin/gui-app \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --prefix GIO_EXTRA_MODULES : "${lib.getLib dconf}/lib/gio/modules"
  '';

  # Ensure icon and mime databases are in closure
  preFixup = ''
    mkdir -p $out/nix-support
    echo ${hicolor-icon-theme} >> $out/nix-support/runtime-deps
    echo ${shared-mime-info} >> $out/nix-support/runtime-deps
  '';
}
```

### Electron Applications

Electron apps bundle their runtime but may need system libraries:

```nix
{ stdenv, makeWrapper, electron, libpulseaudio, libnotify }:

stdenv.mkDerivation {
  pname = "electron-app";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/app
    cp -r app/* $out/share/app/

    makeWrapper ${electron}/bin/electron $out/bin/electron-app \
      --add-flags "$out/share/app" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libpulseaudio libnotify ]}"
  '';
}
```

### Shell Scripts with Many Tools

Scripts using many utilities:

```nix
{ stdenv, lib, makeWrapper, coreutils, findutils, gnugrep, gnused, gawk }:

stdenv.mkDerivation {
  pname = "toolbox-script";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp script.sh $out/bin/toolbox

    wrapProgram $out/bin/toolbox \
      --prefix PATH : ${lib.makeBinPath [
        coreutils
        findutils
        gnugrep
        gnused
        gawk
      ]}
  '';
}
```

## Debugging Runtime Dependency Issues

### Program Can't Find Shared Library

```bash
$ ./result/bin/myapp
error while loading shared libraries: libfoo.so.1: cannot open shared object file
```

TODO: Link to dedicated page about handling library resolution

### Program Executes but Can't Find Helper Tools

```bash
$ ./result/bin/myscript
grep: command not found
```

**Solution**: Wrap the program to provide tools on PATH:

```nix
postInstall = ''
  wrapProgram $out/bin/myscript \
    --prefix PATH : ${lib.makeBinPath [ gnugrep ]}
'';
```


### Unexpected Large Closure

```bash
$ nix path-info -Sh ./result
./result    2.3G    # Way too large!
```

**Solution**: Find the culprit:

```bash
# List closure sorted by size
$ nix path-info -rSh ./result | sort -h

# Check why a large package is included
$ nix why-depends --precise ./result /nix/store/xxx-large-package
```

## Summary

Runtime dependencies in nix are:

1. **Automatically detected**: Nix scans outputs for store path references
2. **Inspectable**: Use `nix-store -q --references` and `--requisites`
3. **Explicitly controllable**: Use `wrapProgram` for environment setup
4. **Can be forced**: Write references to `$out/nix-support` when needed
5. **May need patching**: Fix shebangs and hardcoded paths
6. **Should be minimized**: Smaller closures are faster to deploy

Understanding runtime dependencies helps you create packages that work reliably
in nix's isolated environment while keeping deployments efficient.
