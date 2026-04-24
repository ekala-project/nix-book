# Alternative Package Sets

Importing nixpkgs with a different configuration produces an entirely different
package set. Nixpkgs takes advantage of this to expose several pre-configured
package sets as attributes directly on `pkgs`. These cover the most common
reasons you might want a non-default build: static linking, a different libc,
or a different target architecture.

Because these sets are just nixpkgs imported with different parameters, they
compose naturally with the rest of the package set. You can mix packages from
multiple sets in the same derivation, using the alternative set only where it
is needed.

## pkgsStatic

`pkgs.pkgsStatic` contains packages built with static linking against musl
libc. Statically linked binaries have no runtime dependencies on shared
libraries, making them easy to distribute and deploy to systems that may not
have the same libraries installed.

```nix
# A statically linked hello binary
pkgs.pkgsStatic.hello

# Use it as a build input
stdenv.mkDerivation {
  name = "my-tool";
  buildInputs = [ pkgs.pkgsStatic.zlib ];
}
```

Static builds work well for self-contained command-line tools but are
unsupported or broken for many packages — particularly those with mandatory
shared library dependencies, plugins, or C extensions. Expect to encounter
build failures and treat them as exceptions to fix rather than the norm.

## pkgsMusl

`pkgs.pkgsMusl` is similar to `pkgsStatic` but produces dynamically linked
binaries against musl libc instead of glibc. This is useful when you want the
size and compatibility characteristics of musl without full static linking:

```nix
pkgs.pkgsMusl.curl
```

## pkgsCross

`pkgs.pkgsCross` contains package sets for cross-compilation targets. Each
attribute is a full nixpkgs instance configured to produce binaries for that
target while running on the host machine.

```nix
# Produce an aarch64 binary on an x86_64 machine
pkgs.pkgsCross.aarch64-multiplatform.hello

# Produce a RISC-V binary
pkgs.pkgsCross.riscv64.hello

# Produce a Windows binary (using mingw)
pkgs.pkgsCross.mingwW64.hello
```

Some commonly used targets:

| Attribute | Target |
|-----------|--------|
| `aarch64-multiplatform` | 64-bit ARM Linux |
| `aarch64-multiplatform-musl` | 64-bit ARM Linux with musl |
| `riscv64` | 64-bit RISC-V Linux |
| `mingwW64` | 64-bit Windows (MinGW) |
| `raspberryPi` | ARMv6 Linux (Raspberry Pi) |
| `s390x` | IBM Z (s390x) Linux |

Cross-compilation support varies significantly by package. Well-maintained
packages in nixpkgs generally cross-compile cleanly. Packages with complex
build systems, bundled dependencies, or build-time execution of compiled code
are more likely to fail. As with static builds, treat breakages as fixable
exceptions rather than reasons to avoid cross-compilation entirely.

## Combining alternative sets

Alternative sets can be used as build inputs in ordinary derivations, which is
the most common pattern. You do not need to switch your entire build to a
cross or static set — just reach into the alternative set for the specific
package you need:

```nix
stdenv.mkDerivation {
  name = "firmware-bundle";

  # Compile the firmware for ARM, the rest of the build runs natively
  buildInputs = [
    pkgs.pkgsCross.aarch64-multiplatform.openssl
  ];
}
```

## A note on polish

The native `x86_64-linux` and `aarch64-linux` package sets are the most
thoroughly tested and receive the most attention from the nixpkgs community.
Alternative sets — particularly cross-compilation targets and static builds —
are less consistently maintained. Some packages have never been tested in these
configurations and will fail. If you hit a build failure in an alternative set,
check the nixpkgs issue tracker and, if no fix exists, consider contributing
one — these configurations improve primarily through users reporting and fixing
breakages.
