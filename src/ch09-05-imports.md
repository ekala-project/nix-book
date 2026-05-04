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
`config` values, and by extension `pkgs`, to decide what to import — the import list must be statically
known. For conditional behaviour, use `mkIf` inside the imported module rather
than importing conditionally.

If you genuinely need to select between two modules based on some value, encode
the condition in a Nix `if` expression using only values available before
evaluation:

```nix
{ config, ... }:

{
  imports = [
    # Fails with infinite recursion. `pkgs` derives from `config.nixpkgs.pkgs` which creates
    # a strong cycle between imports and config
    (if pkgs.stdenv.isLinux then ./linux.nix else ./darwin.nix)
  ];

  # Better alternative, config can alter other config values
  config.programs.steam.enable = pkgs.stdenv.hostPlatform.isLinux;
}
```

If you truly want conditional imports, you must use `specialArgs` when evaluating the NixOS modules:
```nix
# flake.nix
nixosConfigurations.work = nixpkgs.lib.nixosSystem rec {
  system = "x86_64-linux";
  specialArgs = { isLocal = true; };
  modules = [
    ./configuration.nix
  ];
};

# In any module
{ config, lib, pkgs, isLocal, ... }:

{
  imports = if isLocal then [
    ./local-profile.nix
  ] else [
    ./remote-profile.nix
  ];
}
```

`specialArgs` can be thought of as defined before any module logic. Thus they exist
outside of the fixed point resolution for `config`, `options`, or `pkgs`.

**Note:** Often it is easier to just do all imports at the top-level, instead of branching logic in modules
```nix
# Alternative to do decision making at the module level, you can do it as the system level as well.
nixosConfigurations.work = nixpkgs.lib.nixosSystem rec {
  system = "x86_64-linux";
  modules = [
    ./shared-configuration.nix
    ./local-profile.nix
  ];
};

nixosConfigurations.remote = nixpkgs.lib.nixosSystem rec {
  system = "x86_64-linux";
  modules = [
    ./shared-configuration.nix
    ./remote-profile.nix
  ];
};
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

# [Dendritic pattern](https://discourse.nixos.org/t/the-dendritic-pattern/61271)

Instead of using `specialArgs` or configuring imports, the module system does allow
for arbitrary options to be defined, thus using the local vs remote example earlier:

```nix
# modules/common.nix
{
  # option which is now available in all modules
  options.isLocalSystem = lib.mkEnableOption { };
}

# modules/packages.nix
{
  config.programs.steam.enable = config.isLocalSystem;
}
```

The advantage of the dendritic paradigm is that you have finer granular toggles
which can be used to configure options. So cross cutting concerns like 
"enable some shared database for many services" can have a separate toggle which
then your other modules can respect.

NixOS modules coming from nixpkgs don't have the luxury to know how they will be
used so they are often very verbose and expose a lot of options which may or may
not be relevant to a use case. The Dendritic pattern lies between these vanilla option
modules and specialized profiles, allowing for a middle ware of grouping concerns
which are common across many different configurations.
