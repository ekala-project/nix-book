# Imports

The `imports` list tells the module system which other modules to include. All
imported modules are merged together as if they had been written in a single
file. Imports are the primary mechanism for composing a NixOS configuration
from reusable pieces.

## Basic imports

```nix
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./users.nix
  ];
}
```

Paths in `imports` can be:

- **Relative paths** — resolved relative to the file containing the `imports`
  list
- **Absolute paths** — used as-is
- **Module values** — a Nix expression that evaluates to a module (a function
  or attribute set); used when importing from flake inputs or nixpkgs

## Importing from nixpkgs

NixOS modules from nixpkgs are imported automatically and do not need to be
listed. For third-party modules shipped as a nixpkgs overlay or a separate
path:

```nix
imports = [
  "${inputs.some-flake}/modules/mymodule.nix"
];
```

## Importing inline modules

An element of `imports` can be a module value directly, not just a path:

```nix
imports = [
  # Inline module — useful for small conditional inclusions
  ({ lib, ... }: {
    networking.firewall.enable = lib.mkDefault true;
  })
];
```

## Conditional imports

The module system evaluates `imports` before options, so you cannot use
`config` values to decide what to import — the import list must be statically
known. For conditional behaviour, use `mkIf` inside the imported module rather
than importing conditionally.

If you genuinely need to select between two modules based on some value, encode
the condition in a Nix `if` expression using only values available before
evaluation (such as `pkgs.stdenv.isLinux`):

```nix
imports = [
  (if pkgs.stdenv.isLinux then ./linux.nix else ./darwin.nix)
];
```

## Import order and duplicates

The module system deduplicates imports: if the same file or module value is
imported more than once (from different places in the tree), it is only
evaluated once. This means you can safely import a shared module from multiple
places without worrying about double-application.

Import order does not affect the final result for most configuration — merging
is commutative for the common types. Order only matters for `mkOrder`, which is
covered in the merging chapter.

## Structuring a configuration with imports

A common pattern is a top-level `configuration.nix` that delegates to
per-concern files:

```
/etc/nixos/
├── configuration.nix   # imports everything else
├── hardware-configuration.nix
├── networking.nix
├── users.nix
├── services/
│   ├── nginx.nix
│   └── postgresql.nix
└── profiles/
    └── workstation.nix
```

```nix
# configuration.nix
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./users.nix
    ./services/nginx.nix
    ./services/postgresql.nix
    ./profiles/workstation.nix
  ];
}
```

Each file focuses on one concern and can be added, removed, or shared between
machines independently.

## Importing modules from flakes

When using NixOS flakes, modules from external inputs are imported by
passing them through `nixosSystem`:

```nix
# flake.nix
{
  inputs.home-manager.url = "github:nix-community/home-manager";

  outputs = { nixpkgs, home-manager, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
      ];
    };
  };
}
```

The `modules` argument to `nixosSystem` is equivalent to a top-level `imports`
list. All modules passed here are merged together with the NixOS module
collection.
