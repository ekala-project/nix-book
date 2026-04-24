# Nixpkgs Config

The `config` argument to nixpkgs is an attribute set of high-level policy
values that affect the entire package set. It controls things like which
licence categories are permitted, which packages are allowed despite known
issues, and how certain packages are built by default.

Internally, nixpkgs evaluates `config` through `evalModules`, the same module
system covered in the NixOS chapter. This means every config value has a
declared type and default, and the merged result is always available at
`pkgs.config` — you can inspect it at any time to see what policy is in effect.

## Passing config

Config is passed at import time:

```nix
pkgs = import nixpkgs {
  system = "x86_64-linux";
  config = {
    allowUnfree = true;
  };
};
```

On NixOS, it is set declaratively and applies to the system's nixpkgs instance:

```nix
nixpkgs.config.allowUnfree = true;
```

## Common config options

### allowUnfree

Nixpkgs marks packages with non-free licences as unfree. By default, attempting
to build them raises an error. Setting `allowUnfree = true` permits all unfree
packages:

```nix
config.allowUnfree = true;
```

For finer control, `allowUnfreePredicate` accepts a function that receives the
package and returns a bool. This lets you allowlist specific packages rather
than all unfree software:

```nix
config.allowUnfreePredicate = pkg: builtins.elem (pkg.pname or pkg.name) [
  "steam"
  "nvidia-x11"
];
```

### allowBroken

Packages marked `broken = true` in nixpkgs are expected to fail to build.
Attempting to use them raises an error by default. This flag overrides that:

```nix
config.allowBroken = true;
```

This should be used with caution — packages are marked broken for a reason.
Prefer finding an alternative or fixing the package rather than enabling this
globally.

### permittedInsecurePackages

Packages with known security vulnerabilities are marked insecure and blocked by
default. Individual packages can be permitted by name and version:

```nix
config.permittedInsecurePackages = [
  "openssl-1.1.1w"
  "python-2.7.18.8"
];
```

### allowAliases

Nixpkgs maintains aliases for renamed or removed packages so that old attribute
names still evaluate (to an error with a helpful message). Setting
`allowAliases = false` removes these aliases from the package set, which can
speed up evaluation in large configurations:

```nix
config.allowAliases = false;
```

### packageOverrides

`packageOverrides` is an older mechanism for modifying packages that predates
overlays. It accepts a function from the final package set to an attribute set
of overrides:

```nix
config.packageOverrides = pkgs: {
  hello = pkgs.hello.overrideAttrs (old: {
    doCheck = false;
  });
};
```

For anything beyond trivial one-off overrides, prefer overlays — they compose
correctly, are applied in a defined order, and are the modern standard. See the
[Overlays](./ch08-06-overlays.md) section.

## Inspecting the active config

Because `config` is evaluated as a module, the full resolved configuration is
always available on `pkgs.config`:

```nix
nix-repl> pkgs.config.allowUnfree
false

nix-repl> pkgs.config.permittedInsecurePackages
[ ]
```

This is useful when debugging unexpected build errors — checking `pkgs.config`
confirms whether a policy flag has been applied as intended.

## Common issues

### Unfree error in a flake

Flakes evaluate purely, so nixpkgs config cannot be read from `~/.config/nixpkgs/config.nix`.
You must pass it explicitly when importing nixpkgs:

```nix
pkgs = import nixpkgs {
  system = "x86_64-linux";
  config.allowUnfree = true;
};
```

Forgetting this is the most common reason an unfree package builds in a
non-flake context but fails inside a flake.
