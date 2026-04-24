# Importing Nixpkgs

Nixpkgs is a function. When you `import` it you get back a function that
accepts a configuration argument and returns a package set:

```nix
let
  pkgs = import <nixpkgs> { };
in
pkgs.hello
```

The `{ }` is the configuration argument. Passing an empty set is fine — nixpkgs
supplies sensible defaults for everything. The result, `pkgs`, is the attribute
set of packages you are already familiar with from the rest of this book.

## The configuration argument

The configuration argument accepts three main attributes:

```nix
import <nixpkgs> {
  system   = "x86_64-linux";
  config   = { ... };
  overlays = [ ... ];
}
```

### system

`system` tells nixpkgs which platform to build packages for. It defaults to
the platform of the machine running Nix using `builtins.currentSystem`. You usually do not need to set this
explicitly, but it is important when producing packages for a different
architecture or when the same nixpkgs import is shared across machines:

```nix
pkgs = import <nixpkgs> { system = "aarch64-linux"; };
```

### config

`config` is an attribute set of high-level policy flags. The most commonly
needed ones are:

```nix
pkgs = import <nixpkgs> {
  config = {
    # Allow packages with an unfree licence to be built
    allowUnfree = true;

    # Allow packages marked as broken (likely marked broken for a good reason)
    allowBroken = false;

    # Allow specific packages with known security vulnerabilities
    permittedInsecurePackages = [
      "openssl-1.1.1w"
    ];
  };
};
```

Config is covered in full in the [Nixpkgs Config](./ch08-05-nixpkgs-config.md)
section.

### overlays

`overlays` is a list of functions that modify or extend the package set. They
are the primary mechanism for adding your own packages or overriding existing
ones:

```nix
pkgs = import <nixpkgs> {
  overlays = [ (self: super: { hello = super.hello.override { ... }; }) ];
};
```

Overlays are covered in full in the [Overlays](./ch08-06-overlays.md) section.

## What import returns

The result of `import <nixpkgs> { }` is a large attribute set. The attributes
you will reach for most often are:

| Attribute | Description |
|-----------|-------------|
| `pkgs.<name>` | Individual packages (`pkgs.git`, `pkgs.python3`, …) |
| `pkgs.lib` | The nixpkgs standard library of Nix functions |
| `pkgs.stdenv` | The default build environment |
| `pkgs.callPackage` | Function for calling package expressions with nixpkgs dependencies |
| `pkgs.buildEnv` | Merge multiple packages into one store path |

## Importing multiple times

Each call to `import <nixpkgs> { ... }` produces an independent package set.
This is how you can have two different configurations of nixpkgs in the same
expression — for example, one with `allowUnfree = true` for a specific package
and one without for everything else:

```nix
let
  pkgs       = import <nixpkgs> { };
  unfreePkgs = import <nixpkgs> { config.allowUnfree = true; };
in
{
  environment.systemPackages = [
    pkgs.git
    unfreePkgs.steam
  ];
}
```

**Note:** Importing a new package set does come with time and memory costs. Try
to avoid importing additional package sets.

In practice, most people will just import the package set with unfree packages as
the free packages are not affected by enabling this flag.
