# Merging and Precedence

When multiple modules assign values to the same option, the module system must
combine them into a single result. The rules for how this happens depend on the
option's type and on the priority of each assignment. Understanding merging and
precedence is essential for writing modules that interact correctly with the
rest of a configuration.

## How merging works by type

Each option type defines its own merge behaviour:

| Type | Merge behaviour |
|------|----------------|
| `bool` | All assignments must be equal, or one must win by priority |
| `str` | All assignments must be equal, or one must win by priority |
| `lines` | Assignments are joined with newlines |
| `listOf T` | Assignments are concatenated |
| `attrsOf T` | Assignments are merged by key; conflicts per-key follow T's rules |
| `submodule` | Assignments are merged recursively as nested modules |
| `package` | All assignments must be equal, or one must win by priority |
| `anything` | Best-effort merge; conflicts raise errors |

### Lists accumulate

Because `listOf` concatenates all assignments, multiple modules can each
contribute to the same list without conflict:

```nix
# module-a.nix
environment.systemPackages = [ pkgs.git ];

# module-b.nix
environment.systemPackages = [ pkgs.vim ];

# result
environment.systemPackages = [ pkgs.git pkgs.vim ];
```

The order of items within the final list reflects the order in which modules
were imported, though this is usually not significant.

### Attribute sets merge by key

Each key in an `attrsOf` value is merged independently. Two modules can both
assign to `users.users` as long as they use different keys:

```nix
# module-a.nix
users.users.alice = { isNormalUser = true; };

# module-b.nix
users.users.bob = { isNormalUser = true; };
```

If two modules assign the same key, merging falls back to the value type's
rules. For submodule values this means recursive merging, which usually works.
For scalar values it is a conflict unless resolved by priority.

## Priority

Every assignment carries a numeric priority. When a scalar option receives
multiple assignments, the one with the lowest priority number wins. If two
assignments share the same priority, evaluation fails with a conflict error.

The named priority helpers are:

```nix
lib.mkDefault value   # priority 1000 — easy to override
value                 # priority 100  — normal assignment
lib.mkForce value     # priority 50   — hard to override
lib.mkOverride n v    # priority n    — explicit
```

### Typical use of mkDefault

Module authors use `mkDefault` for sensible defaults that user configuration
should be able to override without ceremony:

```nix
# In a module
config = lib.mkIf config.services.myapp.enable {
  networking.firewall.allowedTCPPorts = lib.mkDefault [ 8080 ];
};

# In the user's configuration.nix — overrides the mkDefault silently
networking.firewall.allowedTCPPorts = [ 9000 ];
```

### Typical use of mkForce

`mkForce` is used when a value must not be changed by user configuration — for
example, a security policy module that must enforce a setting regardless of
what else is imported:

```nix
config.services.openssh.settings.PermitRootLogin = lib.mkForce "no";
```

The user can still override a `mkForce` value, but only with another
`mkForce`, making the conflict visible:

```nix
# Explicit disagreement — both parties know this is an override
services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
```

## mkOrder

Within a `listOf` option, the order of items usually does not matter. When it
does, `lib.mkOrder` controls where a module's contribution is placed in the
final list:

```nix
# Prepend to the list, regardless of import order
boot.kernelModules = lib.mkOrder 500 [ "vfio" "vfio_iommu_type1" ];

# Default order is 1000
boot.kernelModules = [ "kvm-intel" ];
```

Lower order numbers appear earlier in the final list. `mkBefore` and `mkAfter`
are convenience wrappers:

```nix
boot.kernelModules = lib.mkBefore [ "vfio" ];   # order 500
boot.kernelModules = lib.mkAfter  [ "kvm-amd" ]; # order 1500
```

## mkOverride for fine-grained control

When the named helpers are not specific enough, `mkOverride` accepts an
explicit priority number:

```nix
# Between mkDefault (1000) and a normal assignment (100)
networking.hostName = lib.mkOverride 500 "fallback-host";
```

This is rarely needed outside of framework code.

## Debugging merge conflicts

When the module system reports a conflict, the error message shows which files
contributed conflicting values:

```
error: The option 'services.openssh.settings.PermitRootLogin' has
conflicting definition values:
  - In '/etc/nixos/configuration.nix': "no"
  - In '/etc/nixos/hardening.nix': "prohibit-password"
```

The fix is to decide which value should take precedence and wrap it with
`mkForce`, or to remove the duplicate assignment. The `nixos-option` command
can show all assignments to an option and their priorities:

```
$ nixos-option services.openssh.settings.PermitRootLogin
```
