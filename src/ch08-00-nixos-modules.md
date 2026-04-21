# NixOS Modules

So far we have focused on Nix as a build tool: writing derivations, packaging
software, and composing packages together. NixOS takes this further by using
Nix to describe entire system configurations — the services that run, the users
that exist, the kernel parameters, network interfaces, and everything else that
defines an operating system.

The mechanism that makes this possible is the **module system**. Rather than
one monolithic configuration file, a NixOS system is assembled from many small,
composable modules. Each module declares the options it introduces and the
configuration it contributes. The module system evaluates all of them together,
merges their contributions, and produces a consistent system configuration.

This design has several practical benefits:

- **Separation of concerns**: each module is responsible for one aspect of the
  system. A module for a web server does not need to know anything about
  the firewall module, yet the two can interact through well-defined options.
- **Reuse**: modules can be shared across machines. A module that configures
  your preferred editor or your SSH hardening policy can be imported wherever
  it is needed.
- **Discoverability**: options are typed and documented. `nixos-option` and the
  online NixOS manual are generated directly from option declarations.
- **Safety**: the type system catches many configuration mistakes at evaluation
  time, before any changes are applied to the system.

The module system is not exclusive to NixOS. The same machinery is used by
Home Manager (for user-level configuration), NixOS container definitions,
and a growing number of third-party tools. Understanding it once gives you a
foundation that transfers across the whole ecosystem.

This chapter works through the module system from first principles. We start
with how the system is structured, move through options and their types, cover
how modules are composed and how conflicts are resolved, and finish by writing
and testing a complete module from scratch.
