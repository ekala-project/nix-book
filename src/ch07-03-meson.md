# Meson

Meson is a modern build system designed to be fast, user-friendly, and correct. It was
created to address shortcomings in older build systems like autotools and CMake, with
a focus on speed and ease of use. Meson uses the Ninja build backend by default,
resulting in very fast incremental builds.

Key advantages of Meson include:
- Fast builds through Ninja backend
- Simple, readable build definitions in Python-like syntax
- Strong emphasis on correctness and reproducibility
- Excellent cross-compilation support
- Native support for modern language features

Meson is increasingly popular for systems programming projects, particularly in the
GNOME ecosystem and other modern C/C++ projects.

## Basic Meson package

Meson support in nixpkgs requires both `meson` and `ninja` in `nativeBuildInputs`.
The meson setup hook automatically configures the build system:

```nix
{ lib, stdenv, fetchFromGitHub, meson, ninja }:

stdenv.mkDerivation rec {
  pname = "example";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ meson ninja ];

  meta = with lib; {
    description = "An example Meson project";
    license = licenses.mit;
  };
}
```

The Meson hook handles the build phases automatically:
- Configure phase: Runs `meson setup` to generate build files
- Build phase: Runs `ninja` to compile the project
- Install phase: Runs `ninja install` to install files

## Meson configuration options

Meson uses `-D` flags to set build options. These are passed using `mesonFlags`:

```nix
{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config }:

stdenv.mkDerivation rec {
  pname = "myapp";
  version = "2.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];

  mesonFlags = [
    "-Dfeature=enabled"
    "-Dtests=disabled"
    "-Ddocs=false"
  ];

  meta = with lib; {
    description = "Example with Meson flags";
    license = licenses.gpl3;
  };
}
```

### Common Meson options

Meson projects typically use standardized option types: `feature` (enabled/disabled/auto),
`boolean` (true/false), `combo` (enumerated choices), `string`, and `integer`.

**Build type:**
```nix
mesonFlags = [
  "-Dbuildtype=release"  # plain, debug, debugoptimized, release, minsize
];
```

Note: nixpkgs sets this automatically based on build settings.

**Disable tests and documentation:**
```nix
mesonFlags = [
  "-Dtests=disabled"
  "-Ddocs=disabled"
];
```

**Enable or disable features:**
```nix
mesonFlags = [
  "-Dfeature_name=enabled"   # Force feature on
  "-Doptional_feature=auto"  # Enable if dependencies available
  "-Dunwanted=disabled"      # Force feature off
];
```

**Library preferences:**
```nix
mesonFlags = [
  "-Duse_system_libs=true"
  "-Dprefer_static=false"
];
```

**Installation directories:**
```nix
mesonFlags = [
  "-Dbindir=bin"
  "-Dlibdir=lib"
  "-Dincludedir=include"
];
```

These are usually set correctly by default through Meson's standard directory options.

## Meson build types

Meson supports several predefined build types that control optimization and debug info:

- `plain`: No added flags
- `debug`: Minimal optimization, full debug info
- `debugoptimized`: Optimization with debug info (default)
- `release`: Full optimization, no debug info
- `minsize`: Optimize for size

The meson hook in nixpkgs typically sets appropriate defaults, but you can override:

```nix
mesonBuildType = "release";
```

## Finding dependencies

Meson projects use `dependency()` to find libraries. Dependencies should be in
`buildInputs` (libraries) or `nativeBuildInputs` (tools):

```nix
{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config
, glib, gtk3, libxml2
}:

stdenv.mkDerivation rec {
  pname = "myproject";
  version = "3.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ glib gtk3 libxml2 ];

  meta = with lib; {
    description = "GTK application with multiple dependencies";
    license = licenses.lgpl2Plus;
  };
}
```

Note that `pkg-config` is frequently needed with Meson projects, as it's the primary
mechanism for finding dependencies.

## Common issues and fixes

### Missing pkg-config

Meson relies heavily on pkg-config for dependency discovery. If you see errors about
missing dependencies that are actually in `buildInputs`, add pkg-config:

```nix
nativeBuildInputs = [ meson ninja pkg-config ];
```

### Dependency not found

If Meson can't find a dependency through pkg-config, you may need to help it:

```nix
mesonFlags = [
  "-Dlibfoo=enabled"
];

# Or set PKG_CONFIG_PATH
preConfigure = ''
  export PKG_CONFIG_PATH="${lib.getDev somelibrary}/lib/pkgconfig:$PKG_CONFIG_PATH"
'';
```

### Tests fail or require network access

Disable tests if they're problematic:

```nix
mesonFlags = [ "-Dtests=disabled" ];

# Or don't run them even if built
doCheck = false;
```

For projects that hardcode test execution, you might need to patch `meson.build`:

```nix
postPatch = ''
  # Disable test subdirectory
  substituteInPlace meson.build \
    --replace "subdir('tests')" ""
'';
```

### Introspection and cross-compilation

When cross-compiling, disable introspection if it causes issues:

```nix
mesonFlags = [
  "-Dintrospection=disabled"
];
```

### Unwanted dependencies

Some Meson projects auto-detect optional dependencies. Explicitly disable them:

```nix
mesonFlags = [
  "-Doptional_feature=disabled"
];
```

### Documentation build failures

Documentation builds often require tools like doxygen or sphinx. Either add them or
disable docs:

```nix
# Disable
mesonFlags = [ "-Ddocs=disabled" ];

# Or add dependencies
nativeBuildInputs = [ meson ninja pkg-config sphinx ];
mesonFlags = [ "-Ddocs=enabled" ];
```

### Install paths issues

Some projects may install files to unexpected locations. Fix in post-install:

```nix
postInstall = ''
  mkdir -p $out/bin
  mv $out/usr/local/bin/* $out/bin/ || true
'';
```

### Subprojects and wraps

Meson supports "wraps" for bundled dependencies. To use system libraries instead:

```nix
postPatch = ''
  # Remove wrap files to force system dependencies
  rm -rf subprojects/*.wrap
'';

mesonFlags = [
  "-Ddefault_library=shared"
  "--wrap-mode=nodownload"  # Prevent downloading dependencies
];
```

## Detailed example

Here's a comprehensive example of a Meson-based GTK application with multiple
dependencies and configuration options:

```nix
{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, wrapGAppsHook
, desktop-file-utils
, appstream-glib
, glib
, gtk4
, libadwaita
, json-glib
, sqlite
, curl
}:

stdenv.mkDerivation rec {
  pname = "example-gtk-app";
  version = "2.5.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "gtk-app";
    rev = "v${version}";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wrapGAppsHook      # Wrapper for GTK apps
    desktop-file-utils # Desktop file validation
    appstream-glib     # AppStream metadata validation
  ];

  buildInputs = [
    glib
    gtk4
    libadwaita
    json-glib
    sqlite
    curl
  ];

  mesonFlags = [
    "-Dbuildtype=release"
    "-Dtests=disabled"        # Disable tests for this build
    "-Dprofile=default"       # Use default profile (vs. development)
    "-Dnetwork_backend=curl"  # Choose curl over other backends
  ];

  # Meson projects often validate desktop files and appstream data
  # during build, which may fail in sandbox
  postPatch = ''
    # Don't fail build on validation warnings
    substituteInPlace meson.build \
      --replace "error_on_warning: true" "error_on_warning: false"
  '';

  # Run tests (if we enabled them)
  # doCheck = true;

  postInstall = ''
    # Ensure all expected files are in place
    test -f $out/bin/${pname}
    test -f $out/share/applications/${pname}.desktop
    test -f $out/share/icons/hicolor/scalable/apps/${pname}.svg
  '';

  meta = with lib; {
    description = "Example GTK4/Libadwaita application";
    longDescription = ''
      A feature-rich GTK4 application demonstrating modern GNOME
      application development with Meson build system.
    '';
    homepage = "https://github.com/example/gtk-app";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
```

## Summary

Meson provides a modern, fast build system with excellent nixpkgs integration:
- Always include both `meson` and `ninja` in `nativeBuildInputs`
- Add `pkg-config` for dependency discovery in most projects
- Use `mesonFlags` to configure build options with `-D` flags
- Meson's standardized option types (feature/boolean/combo) provide consistency
- The build system is considered the modern replacement for C/C++ projects
- Cross-compilation and reproducibility are first-class features in Meson
