# Autotools

Although autotools has largely been deprecated in favor of newer build systems,
it's still commonly used in GNU and other foundational projects. The GNU build
system (autotools) consists of autoconf, automake, and libtool which together
generate portable Makefiles from template files.

## Basic autotools package

Many autotools-based packages work out of the box with `stdenv.mkDerivation` since
stdenv includes built-in support for the standard `./configure && make && make install`
workflow. Here's a simple example:

```nix
{ lib, stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "hello";
  version = "2.12";

  src = fetchurl {
    url = "mirror://gnu/hello/${pname}-${version}.tar.gz";
    sha256 = "1ayhp9v4m4rdhjmnl2bq3cibrbqqkgjbl3s7yk2nhlh8vj3ay16g";
  };

  meta = with lib; {
    description = "A program that produces a familiar, friendly greeting";
    homepage = "https://www.gnu.org/software/hello/";
    license = licenses.gpl3Plus;
  };
}
```

For packages that ship with pre-generated `configure` scripts (typically in release tarballs),
no additional configuration is needed. stdenv will automatically run `./configure`,
`make`, and `make install` during the appropriate build phases.

## Using autoreconfHook

Some projects require regenerating the build system files before building. This is
common when:
- Packaging from a Git repository instead of a release tarball
- The distributed tarball is missing generated autotools files
- You need to apply patches that modify `configure.ac` or `Makefile.am`

In these cases, use `autoreconfHook` to regenerate the configure script and related files:

```nix
{ lib, stdenv, fetchFromGitHub, autoreconfHook }:

stdenv.mkDerivation rec {
  pname = "example";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ autoreconfHook ];

  meta = with lib; {
    description = "An example autotools project";
    license = licenses.mit;
  };
}
```

The `autoreconfHook` will automatically run `autoreconf -vfi` before the configure phase,
which regenerates all the necessary build system files.

## VCS sources vs release tarballs

Software distributions often provide two types of source archives:

1. **Release tarballs**: Pre-built archives containing generated `configure` scripts
   and Makefile templates. These are ready to build with just `./configure && make`.

2. **VCS snapshots**: Direct exports from version control (Git, SVN, etc.) that
   contain only the source files and autotools templates (`configure.ac`, `Makefile.am`).
   These require running autotools to generate the build system.

When a project's release tarball is missing autotools-generated files (or the release
tarball is not available), you'll need to fetch from VCS and use `autoreconfHook`:

```nix
{ lib, stdenv, fetchFromGitHub, autoreconfHook, pkgconfig }:

stdenv.mkDerivation rec {
  pname = "some-tool";
  version = "2.1.0";

  # Fetching from VCS instead of release tarball
  src = fetchFromGitHub {
    owner = "upstream";
    repo = pname;
    rev = "v${version}";
    sha256 = "...";
  };

  # Required to regenerate build system from VCS checkout
  nativeBuildInputs = [ autoreconfHook pkgconfig ];

  meta = with lib; {
    description = "Example tool built from VCS";
    license = licenses.gpl2Plus;
  };
}
```

## Common fixes and solutions

### Missing build dependencies

Autotools-based packages often use `pkg-config` to find dependencies. Make sure
to include `pkg-config` in `nativeBuildInputs`:

```nix
nativeBuildInputs = [ autoreconfHook pkg-config ];
buildInputs = [ libfoo libbar ];
```

### Configure flags

Many autotools packages accept flags to customize the build. Common patterns include:

```nix
configureFlags = [
  "--enable-feature"
  "--disable-unwanted"
  "--with-library=${lib.getDev somelibrary}"
  "--without-optional-dep"
];
```

### Parallel building issues

Some older autotools projects have race conditions in parallel builds. If you encounter
random build failures, try disabling parallel building:

```nix
enableParallelBuilding = false;
```

### Missing install directories

Occasionally the install phase fails because the Makefile doesn't create necessary
directories. Use `preInstall` to create them:

```nix
preInstall = ''
  mkdir -p $out/bin $out/share/man/man1
'';
```

### Documentation build failures

Some packages try to build documentation that requires tools not in the build environment.
You can often skip documentation:

```nix
configureFlags = [ "--disable-doc" "--disable-gtk-doc" ];

# or use make flags
makeFlags = [ "DOC=no" ];
```

### Out-of-tree builds

Some autotools projects have issues with in-tree builds. Use `preConfigure` to set up
an out-of-tree build:

```nix
preConfigure = ''
  mkdir build
  cd build
  configureScript=../configure
'';
```

## Summary

Autotools support in nixpkgs is mature and works well for most projects:
- Use `autoreconfHook` when building from VCS or when regeneration is needed
- Prefer release tarballs when available, as they include pre-generated files
- Common issues can usually be solved with configure flags or simple phase hooks
- Check `nixpkgs` for similar packages when encountering build issues
