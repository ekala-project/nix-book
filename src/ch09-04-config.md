# Config

The `config` key in a module is where options are assigned values. While
`options` defines the schema, `config` is where the system actually gets
configured. Most of what you write in a NixOS module — and almost everything
in a user's `configuration.nix` — lives under `config`.

## Basic assignment

Assignments follow the option's path directly:

```nix
{ pkgs, ... }:

{
  config = {
    networking.hostName = "myhost";
    time.timeZone = "Europe/London";
    environment.systemPackages = [ pkgs.git pkgs.vim ];
  };
}
```

When a module contains only `config` and no `options` or `imports`, the
`config` wrapper can be omitted — the module system treats a bare attribute set
as if it were `config`:

```nix
{ pkgs, ... }:

{
  networking.hostName = "myhost";
  environment.systemPackages = [ pkgs.git pkgs.vim ];
}
```

This shorthand is common in user configurations but can cause confusion when a
module also declares options, so modules in shared libraries conventionally
always use the explicit `config = { ... }` form.

## Conditional config with mkIf

It is common for a module's configuration to apply only when an enable option
is set. `lib.mkIf` expresses this:

```nix
{ config, lib, pkgs, ... }:

{
  options.services.myapp.enable = lib.mkEnableOption "myapp";

  config = lib.mkIf config.services.myapp.enable {
    systemd.services.myapp = {
      description = "My Application";
      wantedBy    = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.myapp}/bin/myapp";
    };
  };
}
```

`mkIf` is lazy: the body is not evaluated at all when the condition is `false`.
This avoids evaluation errors in the disabled branch and keeps the module
system efficient.

### mkIf vs if-then-else

Prefer `mkIf` over a bare `if` in `config`:

```nix
# Correct — lazy, integrates with module system priority
config = lib.mkIf condition { ... };

# Also works, but eager — the body is always evaluated
config = if condition then { ... } else { };
```

The difference matters when the disabled branch references options that may not
be defined, or when you need `mkMerge` to combine conditional blocks.

## mkMerge

`lib.mkMerge` combines multiple config attribute sets that would otherwise
conflict:

```nix
config = lib.mkMerge [
  {
    environment.systemPackages = [ pkgs.curl ];
  }
  (lib.mkIf config.services.myapp.enable {
    environment.systemPackages = [ pkgs.myapp ];
    networking.firewall.allowedTCPPorts = [ 8080 ];
  })
];
```

Each element of the list is merged independently. This is the idiomatic way
to express a module with several independent conditional blocks.

## Priority: mkDefault, mkForce, and mkOverride

The module system allows multiple modules to assign the same option. For most
mergeable types (lists, attribute sets) this just accumulates values. For
scalar types (bool, str, int) there can only be one value — conflicts are
resolved by priority.

Every assignment has a numeric priority. Lower numbers win. The module system
defines named priorities:

| Function | Priority | Purpose |
|----------|----------|---------|
| `lib.mkDefault` | 1000 | Provide a fallback that users can easily override |
| *(no wrapper)* | 100 | Normal assignment |
| `lib.mkForce` | 50 | Override user configuration |
| `lib.mkOverride n` | n | Explicit numeric priority |

### mkDefault

Use `mkDefault` for values that should be overridable:

```nix
config = lib.mkIf config.services.myapp.enable {
  networking.firewall.allowedTCPPorts = lib.mkDefault [ 8080 ];
};
```

A user can override this without needing `mkForce`:

```nix
networking.firewall.allowedTCPPorts = [ 9000 ];  # overrides the mkDefault above
```

### mkForce

Use `mkForce` when a value must not be changed by users or other modules:

```nix
# Security module: always disable root login
config.services.openssh.settings.PermitRootLogin = lib.mkForce "no";
```

Overriding a `mkForce` value requires another `mkForce` with equal or lower
priority, which makes the conflict explicit and intentional.

### Conflict errors

If two modules assign the same scalar option at the same priority, the module
system raises an error:

```
error: The option 'networking.hostName' has conflicting definition values:
  - In '/etc/nixos/configuration.nix': "host-a"
  - In '/etc/nixos/extra.nix': "host-b"
```

Resolve this by deciding which value should win and wrapping it in `mkForce`,
or by moving the common configuration to a shared location.

## Assertions and warnings

Modules can validate configuration and surface problems early.

### assertions

`assertions` is a list of `{ assertion = bool; message = str; }` records. Any
false assertion aborts evaluation with the given message:

```nix
config = lib.mkIf config.services.myapp.enable {
  assertions = [
    {
      assertion = config.services.myapp.port != 80 || config.services.nginx.enable;
      message   = "myapp on port 80 requires nginx to be enabled.";
    }
  ];
};
```

### warnings

`warnings` is a list of strings. Each string is printed as a warning during
`nixos-rebuild` but does not abort:

```nix
config.warnings = lib.optional
  (config.services.myapp.dataDir == "/tmp")
  "services.myapp.dataDir is set to /tmp; data will not persist across reboots.";
```
