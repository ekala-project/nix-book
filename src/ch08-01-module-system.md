# The Module System

A NixOS configuration is not a single file — it is a collection of modules
evaluated together by the module system. Understanding what a module is and
how the system processes them is the foundation for everything else in this
chapter.

## What is a module?

At its core, a module is a Nix file that returns an attribute set with up to
three keys:

```nix
{
  imports = [ ... ];   # other modules to include
  options = { ... };   # option declarations
  config  = { ... };   # option assignments
}
```

All three keys are optional. The simplest valid module is an empty attribute
set:

```nix
{ }
```

More commonly, a module is a function that receives the evaluated system
configuration and returns that attribute set:

```nix
{ config, lib, pkgs, ... }:

{
  options = { ... };
  config  = { ... };
}
```

The function arguments are provided by the module system:

| Argument | Description |
|----------|-------------|
| `config` | The fully evaluated configuration (all modules merged) |
| `lib` | The nixpkgs standard library |
| `pkgs` | The nixpkgs package set |
| `options` | The full set of declared options and their metadata |

The `...` at the end of the argument list is important — it allows modules to
be called even when the module system passes arguments the module does not
declare.

## How the module system evaluates modules

When NixOS builds a system configuration, the module system performs these
steps:

1. **Collect** all modules referenced directly or through `imports`
2. **Merge** their `options` declarations into a single option schema
3. **Merge** their `config` assignments according to each option's merge
   semantics
4. **Evaluate** `config` lazily, resolving references between options

The result is a single `config` attribute set that represents the complete,
consistent system configuration.

Because Nix is lazy, options that are never referenced are never evaluated.
This means a module can declare options that only take effect when another
module assigns them.

## The fixed-point

The module system builds `config` as a fixed-point: each module can reference
`config` in its own `config` block, creating apparent circular references.

```nix
{ config, lib, ... }:

{
  config = {
    # This references config.networking.hostName, which may be set
    # by another module or by the user's configuration.
    environment.etc."hostname".text = config.networking.hostName;
  };
}
```

Nix's lazy evaluation resolves these references: as long as there is no true
cycle (A depends on B which depends on A with no base case), evaluation
terminates correctly.

## A minimal working example

The following is a complete, self-contained module that a NixOS configuration
could import:

```nix
# motd.nix
{ config, lib, pkgs, ... }:

{
  options.my.motd = lib.mkOption {
    type = lib.types.str;
    default = "Welcome.";
    description = "Message of the day shown at login.";
  };

  config.environment.etc."motd".text = config.my.motd;
}
```

A user's `configuration.nix` can then import this module and set the option:

```nix
{ ... }:

{
  imports = [ ./motd.nix ];

  my.motd = "Hello, ${config.networking.hostName}!";
}
```

The module system merges both files, resolves all references, and produces the
final `/etc/motd` file as part of the system closure.

## Module locations in nixpkgs

NixOS ships with hundreds of modules covering nearly every aspect of a Linux
system. They live under `nixos/modules/` in the nixpkgs repository and are
automatically imported through `nixos/modules/module-list.nix`. You never need
to import them manually — their options are always available.

Custom modules (your own, or from third-party flakes) must be explicitly listed
in `imports`.
