# Overrides

Overlays let you modify packages across the entire package set. Overrides are
the lower-level mechanism that overlays use: functions attached to individual
derivations that produce a modified copy. You can use overrides directly
without an overlay when you only need to change a package in one place, or
combine them with overlays when the change should propagate globally.

## override

Every package produced by `callPackage` carries an `override` function.
It re-calls the package's function with some of the original arguments replaced.
This is how you substitute a dependency:

```nix
# Use a custom openssl everywhere ffmpeg is called
pkgs.ffmpeg.override {
  openssl = myCustomOpenssl;
}
```

`override` operates on the _inputs_ to the package function — the arguments
that `callPackage` resolved from the package set. It does not touch the
derivation attributes (`src`, `buildPhase`, etc.) directly.

## overrideAttrs

`overrideAttrs` modifies the attribute set passed to `stdenv.mkDerivation`
(or the equivalent builder). It receives a function from the old attributes to
the new ones:

```nix
pkgs.hello.overrideAttrs (old: {
  # Disable the test suite
  doCheck = false;
})
```

The `old` argument contains all attributes as they were before the override,
so you can extend rather than replace:

```nix
pkgs.curl.overrideAttrs (old: {
  # Append to the existing configure flags
  configureFlags = old.configureFlags ++ [ "--without-brotli" ];
})
```

`overrideAttrs` is the right tool when you need to change sources, build flags,
patches, phases, or any other derivation-level attribute.

## Combining both

From a package expression perspective, overrides affect the following areas:

```nix
{
  # These are affected by `.override`
  stdenv,
  openssl,
  ...
}:

stdenv.mkDerivation {
  # These are affected by `.overrideAttrs`
  buildInputs = [ openssl ];
}
```

A common pattern is to use `override` for dependency substitution and
`overrideAttrs` for build-level changes together:

```nix
pkgs.somePackage
  .override      { openssl = pkgs.openssl_3; }
  .overrideAttrs (old: { doCheck = false; });
```

Inside an overlay this looks like:

```nix
final: prev: {
  somePackage = prev.somePackage
    .override      { openssl = final.openssl_3; }
    .overrideAttrs (old: { doCheck = false; });
}
```

## Language-specific overrides

Some build helpers add their own override functions that understand the
language-specific structure of the package. The attrs passed to `stdenv.mkDerivation` are affected by `overrideAttrs`,
so packages with specialized builders built on top of mkDerivation will have behavior which isn't reflected
in calls to `overrideAttrs`. In these cases, there is often a specialized
variant of `overrideAttrs` which is more reflective of the attrs passed to the original
package expression.

### overridePythonAttrs

Python packages built with `buildPythonPackage` carry `overridePythonAttrs`.
It works like `overrideAttrs` but preserves the Python package metadata
(dependencies, Python version, wheel format) that the Python infrastructure
depends on:

```nix
pkgs.python3Packages.requests.overridePythonAttrs (old: {
  doCheck = false;
})
```

Using plain `overrideAttrs` on a Python package will work for simple changes
but can break propagated dependencies and the `withPackages` mechanism.

### overrideModAttrs

Go packages built with `buildGoModule` carry `overrideModAttrs` for modifying
the vendoring derivation specifically — the intermediate step that fetches and
caches Go module dependencies. This is useful when the vendor hash needs to
change independently of the main package attributes:

```nix
pkgs.someGoTool.overrideModAttrs (old: {
  postPatch = old.postPatch or "" + ''
    substituteInPlace go.mod --replace "..." "..."
  '';
})
```

As a general rule, prefer the language-specific override function when one
exists. If you are unsure whether one exists, check whether the package
attribute set contains an `override*` function beyond `override` and
`overrideAttrs`.

## finalAttrs

Derivations declared with `mkDerivation` can use `finalAttrs` to refer to
their own final attribute set, avoiding duplication or invariance when attributes depend on
each other:

```nix
stdenv.mkDerivation (finalAttrs: {
  pname   = "mytool";
  version = "1.0.0";

  src = fetchurl {
    url    = "https://example.com/${finalAttrs.pname}-${finalAttrs.version}.tar.gz";
    sha256 = "...";
  };

  passthru.tests.version = runCommand "test-version" { } ''
    ${finalAttrs.finalPackage}/bin/mytool --version | grep ${finalAttrs.version}
  '';
})
```

`finalAttrs.finalPackage` refers to the fully overridden derivation — not the
pre-override version. This matters for `overrideAttrs`: when a caller overrides
`version`, the `src` URL and the test both see the new value automatically,
because they reference `finalAttrs` rather than a closed-over local variable.

Without `finalAttrs`, overriding `version` alone would leave `src` pointing at
the old URL, a common source of subtle build failures.

## Common mistakes

### Shadowing with final in an overlay

Inside an overlay, using `final` to reference the package you are replacing
causes infinite recursion:

```nix
# Wrong — infinite recursion
final: prev: {
  hello = final.hello.overrideAttrs (old: { doCheck = false; });
}

# Correct — use prev to get the original
final: prev: {
  hello = prev.hello.overrideAttrs (old: { doCheck = false; });
}
```

### Forgetting to thread old attributes

When extending a list or string attribute, always include the original value:

```nix
# Wrong — replaces all patches, discards the originals
overrideAttrs (old: { patches = [ ./my.patch ]; })

# Correct — appends to the existing list
overrideAttrs (old: { patches = old.patches ++ [ ./my.patch ]; })
```

### Using overrideAttrs on language packages

Applying `overrideAttrs` to a Python, Go, or other language package when a
language-specific override exists will work for simple cases but risks dropping
metadata that the language infrastructure relies on. When in doubt, use the
language-specific function.
