# CMake

CMake is a widely-used cross-platform build system generator that creates native
build files (like Makefiles or Ninja build files) from a platform-independent
configuration. It's particularly popular in C and C++ projects, and has become
the de facto standard for many modern projects.

## Basic CMake package

CMake support in nixpkgs is provided through the `cmake` setup hook. Simply adding
`cmake` to `nativeBuildInputs` will configure stdenv to use CMake for the build:

```nix
{ lib, stdenv, fetchFromGitHub, cmake }:

stdenv.mkDerivation rec {
  pname = "example";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ cmake ];

  meta = with lib; {
    description = "An example CMake project";
    license = licenses.mit;
  };
}
```

The CMake hook automatically handles the configure and build phases:
- Configure phase: Runs `cmake` with appropriate flags
- Build phase: Runs `make` (or `ninja` if available)
- Install phase: Runs `make install`

## CMake flags and configuration

CMake uses `-D` flags to set configuration variables. These can be passed using
`cmakeFlags`:

```nix
{ lib, stdenv, fetchFromGitHub, cmake }:

stdenv.mkDerivation rec {
  pname = "myapp";
  version = "2.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = version;
    sha256 = "...";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DENABLE_FEATURE=ON"
    "-DBUILD_TESTING=OFF"
    "-DUSE_SYSTEM_LIBS=ON"
  ];

  meta = with lib; {
    description = "Example with CMake flags";
    license = licenses.asl20;
  };
}
```

### Common CMake toggles

Here are frequently-used CMake variables that control the build:

**Build type:**
```nix
# Expected usage
cmakeFlags = [
  "-DCMAKE_BUILD_TYPE=Release"  # Release, Debug, RelWithDebInfo, MinSizeRel
];

# Build Type is handled as a special case so that it can always be appended last
# Multiple definitions of build type will only have the last occurrence honored.
cmakeBuildType = "Release";
```

**Disable tests:**
```nix
cmakeFlags = [
  "-DBUILD_TESTING=OFF"  # Standard CMake variable, `doCheck = false;` also sets this
  "-DENABLE_TESTS=OFF"   # Some projects use this instead
];
```

**Library selection:**
```nix
cmakeFlags = [
  "-DUSE_SYSTEM_LIBS=ON"        # Use system libraries instead of bundled
  "-DWITH_OPENSSL=${openssl}"   # Specify library location
];
```

**Installation paths:**
```nix
cmakeFlags = [
  "-DCMAKE_INSTALL_BINDIR=bin"
  "-DCMAKE_INSTALL_LIBDIR=lib"
  "-DCMAKE_INSTALL_INCLUDEDIR=include"
];
```

These are usually set correctly by the cmake setup hook, but some packages may need project-specific values.

## Using Ninja instead of Make

CMake can generate Ninja build files instead of Makefiles for faster builds.
Add `ninja` to `nativeBuildInputs` alongside `cmake`:

```nix
{ lib, stdenv, fetchFromGitHub, cmake, ninja }:

stdenv.mkDerivation rec {
  pname = "fast-build";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ cmake ninja ];

  meta = with lib; {
    description = "CMake project using Ninja for faster builds";
    license = licenses.mit;
  };
}
```

The CMake hook will automatically detect Ninja and use it instead of Make.

## Finding dependencies

CMake projects use `find_package()` and related functions to locate dependencies. For this to work in Nix,
dependencies must be in `buildInputs` or `propagatedBuildInputs`:

```nix
{ lib, stdenv, fetchFromGitHub, cmake
, boost, openssl, zlib
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

  nativeBuildInputs = [ cmake ];
  buildInputs = [ boost openssl zlib ];

  meta = with lib; {
    description = "Project with multiple dependencies";
    license = licenses.gpl3;
  };
}
```

For header-only libraries or libraries needed by downstream packages, use
`propagatedBuildInputs` instead:

```nix
propagatedBuildInputs = [ eigen ];  # Header-only library
```

## Common issues and fixes

### CMake can't find dependencies

If CMake fails to find a package even though it's in `buildInputs`, you may need
to help it locate the dependency:

```nix
cmakeFlags = [
  "-DBoost_ROOT=${boost}"
  "-DOPENSSL_ROOT_DIR=${openssl.dev}"
];
```

### Unwanted bundled dependencies

Many CMake projects bundle third-party libraries. It's highly preferable for them to use system libraries:

```nix
postPatch = ''
  # Remove bundled libraries
  rm -rf third_party/zlib third_party/curl
'';

cmakeFlags = [
  "-DUSE_SYSTEM_ZLIB=ON"
  "-DUSE_SYSTEM_CURL=ON"
];
```

### Tests fail or aren't needed

Disable building and running tests if they're problematic or unnecessary:

```nix
cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

# Or keep and build tests but don't run them
doCheck = false;
```

If you want to run tests, ensure test dependencies are available:

```nix
nativeBuildInputs = [ cmake ];
checkInputs = [ gtest ];
doCheck = true;
```

### Install paths are wrong

Some projects hardcode installation paths. Override them with CMake variables or fix
the install phase:

```nix
cmakeFlags = [
  "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
  "-DCMAKE_INSTALL_BINDIR=bin"
  "-DCMAKE_INSTALL_LIBDIR=lib"
];
```

Or fix it in the install phase:

```nix
postInstall = ''
  mkdir -p $out/bin
  mv $out/usr/bin/* $out/bin/
  rm -rf $out/usr
'';
```

### Parallel build failures

While rare with CMake, parallel builds can sometimes cause issues:

```nix
enableParallelBuilding = false;
```

### Cross-compilation issues

When cross-compiling, ensure CMake knows about the target platform. The setup hook
usually handles this, but you may need:

```nix
cmakeFlags = [
  "-DCMAKE_SYSTEM_NAME=${stdenv.hostPlatform.uname.system}"
  "-DCMAKE_SYSTEM_PROCESSOR=${stdenv.hostPlatform.uname.processor}"
];
```

### Build type warnings

Some packages warn about build type not being set. This is usually harmless,
but you can silence it:

```nix
cmakeFlags = [
  "-DCMAKE_BUILD_TYPE=${if stdenv.isDarwin then "Release" else "RelWithDebInfo"}"
];
```

### GUI tools and Qt/GTK

CMake projects using GUI frameworks may need additional setup:

```nix
{ lib, stdenv, fetchFromGitHub, cmake
, qt5  # or gtk3
}:

stdenv.mkDerivation rec {
  pname = "gui-app";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ cmake qt5.wrapQtAppsHook ];
  buildInputs = [ qt5.qtbase qt5.qttools ];

  meta = with lib; {
    description = "Qt-based GUI application";
    license = licenses.lgpl3;
  };
}
```

## Summary

CMake support in nixpkgs is robust and straightforward:
- Add `cmake` to `nativeBuildInputs` to enable CMake support
- Use `cmakeFlags` to pass configuration options via `-D` flags
- Add `ninja` for faster builds
- Most dependency issues can be solved with appropriate CMake flags
- Check existing nixpkgs packages for similar CMake-based projects when troubleshooting
