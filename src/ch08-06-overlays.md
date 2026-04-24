# Overlays

Most package managers treat their package set as a fixed database — you can
install what is in it, but modifying or replacing a package requires forking
the manager or maintaining a separate repository. Nixpkgs takes a different
approach: the entire package set is a Nix value, and overlays let you transform
it with ordinary Nix functions. You can add new packages, replace existing
ones, change build options, or patch sources, and the result is a first-class
package set indistinguishable from the original.

## What an overlay is

An overlay is a function that takes two arguments and returns an attribute set
of packages:

```nix
final: prev: {
  # packages to add or replace
}
```

- **`prev`** is the package set before this overlay was applied. Use it to
  access the original version of a package you are modifying. When changing a package,
  you always want to use `prev` to avoid infinite recursion.
- **`final`** is the package set after all overlays have been applied. Use it
  when you need a dependency that may itself have been modified by another
  overlay. In almost all cases you want to consume packages from `final`, generally
  in the form of `final.callPackage`.

The distinction matters: reaching for `prev.somePackage` gives you the
unmodified package; reaching for `final.somePackage` gives you the
post-overlay version. Using `final` for your own package's dependencies ensures
the full overlay chain is respected.

## How overlays are applied

Nixpkgs applies overlays through a fixed-point fold. Each overlay's result is
merged with the package set and the accumulation is passed as `prev` to the
next overlay. Once all overlays have been applied, the fully merged set is fed back as
`final`. This is the same fixed-point mechanism that makes the NixOS module
system work — apparent circular references resolve correctly because Nix is
lazy.

The practical consequence is that overlays compose: you can have multiple
overlays that each build on each other's results, and the order they are
applied in is well-defined.

The (simplified) implementation of overlays:
```nix
{ overlays }:

let
  # Fold over all overlays so that `prev:` is applied to each. Results in a single `self: { ... }` recursive function.
  toFix = lib.foldl' (lib.flip lib.extends) (self: { }) overlays
  # Apply the recursive function to itself, converging to a "fixed point", works because nix is lazy
  fix = f: let x = f x in x; 
  # "Fixing" results in a single package set, which we commonly refer to as "pkgs"
  pkgs = fix toFix;
in
pkgs
```

## Adding a package

The simplest overlay adds a package that is not in nixpkgs:

```nix
final: prev: {
  myapp = final.callPackage ./myapp.nix { };
}
```

Using `final.callPackage` (not `prev.callPackage`) ensures that `myapp`'s
dependencies are resolved from the fully overlaid package set.

## Modifying an existing package

To change build options on an existing package, use `overrideAttrs`:

```nix
final: prev: {
  hello = prev.hello.overrideAttrs (old: {
    doCheck = false;
  });
}
```

`prev.hello` is used here deliberately — you want the original package as the
base, not a potentially already-modified version. Doing `hello = final.hello.overrideAttrs ( ... );` would result
in infinite recursion.

## Overriding dependencies

`override` changes the inputs (generally other packages) that `callPackage` passed to a package:

```nix
final: prev: {
  # Build ffmpeg against our custom version of x264
  ffmpeg = prev.ffmpeg.override {
    x264 = final.x264-custom;
  };
}
```

## Composing multiple overlays

Overlays are just values in a list, so composing them is straightforward:

```nix
pkgs = import nixpkgs {
  system   = "x86_64-linux";
  overlays = [
    (final: prev: { myapp = final.callPackage ./myapp.nix { }; })
    (final: prev: { mytool = final.callPackage ./mytool.nix { }; })
  ];
};
```

They are applied in list order, left to right, so a later overlay can build on
packages introduced by an earlier one. `lib.composeManyExtensions` can be used to
fold many overlays into what appears to be a single overlay.

## Overlays in a flake

The conventional way to expose an overlay from a flake is through the
`overlays` output:

```nix
outputs = { self, nixpkgs }: {
  overlays.default = final: prev: {
    myapp = final.callPackage ./myapp.nix { };
  };
};
```

Consumers apply it when importing nixpkgs:

```nix
pkgs = import nixpkgs {
  system   = "x86_64-linux";
  overlays = [ anotherFlake.overlays.default ];
};
```

Within the same flake, `self.overlays.default` refers to the overlay:

```nix
outputs = { self, nixpkgs }:
let
  pkgs = import nixpkgs {
    system   = "x86_64-linux";
    overlays = [ self.overlays.default ];
  };
in {
  overlays.default = final: prev: {
    myapp = final.callPackage ./myapp.nix { };
  };

  packages.x86_64-linux.myapp = pkgs.myapp;
};
```

## A note on naming: self/super

Older nixpkgs code and documentation uses `self: super:` for the overlay
arguments instead of `final: prev:`. They mean exactly the same thing — `self`
is `final` and `super` is `prev`. The `final`/`prev` naming was adopted later
as it is more descriptive, and is now the convention in new code.
