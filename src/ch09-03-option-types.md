# Option Types

Every option has a type that controls what values are accepted, how multiple
assignments are merged, and what appears in the generated documentation. Types
are values found under `lib.types`.

## Primitive types

### bool

```nix
type = lib.types.bool;
```

Accepts `true` or `false`. Multiple assignments must agree; conflicting bool
values are an error. Use `mkEnableOption` for the common enable pattern.

### int and variants

```nix
type = lib.types.int;           # any integer
type = lib.types.ints.positive; # integer > 0
type = lib.types.ints.unsigned; # integer >= 0
type = lib.types.ints.between 1 65535;  # inclusive range
type = lib.types.port;          # alias for ints.between 0 65535
```

### float

```nix
type = lib.types.float;
```

### str

```nix
type = lib.types.str;
```

Accepts any string. Multiple assignments to a `str` option are an error; use
`lines` or `commas` if you need accumulation.

### lines

```nix
type = lib.types.lines;
```

Like `str`, but multiple assignments are joined with newlines. Useful for
configuration file sections contributed by multiple modules.

### commas

```nix
type = lib.types.commas;
```

Like `lines` but joined with commas.

### path

```nix
type = lib.types.path;
```

Accepts a filesystem path (a string starting with `/` or a Nix path value).

### enum

```nix
type = lib.types.enum [ "debug" "info" "warn" "error" ];
```

Accepts exactly one of the listed values. The list of valid values appears in
the generated documentation.

### anything

```nix
type = lib.types.anything;
```

Accepts any value. Merging follows the merge rules of the actual runtime type
where possible, falling back to an error on conflict. Useful for
pass-through options whose structure is not known at declaration time.

### raw

```nix
type = lib.types.raw;
```

Like `anything` but explicitly opts out of merging — only one assignment is
permitted. Use this when a value must not be merged under any circumstances.

## Compound types

### nullOr

```nix
type = lib.types.nullOr lib.types.str;
```

Accepts either `null` or a value of the wrapped type. Useful for optional
values with no meaningful default:

```nix
options.services.myapp.apiKey = lib.mkOption {
  type    = lib.types.nullOr lib.types.str;
  default = null;
  description = "API key, or null to disable authentication.";
};
```

### listOf

```nix
type = lib.types.listOf lib.types.str;
```

Accepts a list of values of the given type. Multiple assignments are
concatenated, so several modules can each contribute items to the same list.

### attrsOf

```nix
type = lib.types.attrsOf lib.types.int;
```

Accepts an attribute set where every value has the given type. Assignments from
multiple modules are merged by attribute name; conflicting attributes for the
same key are an error unless the value type allows merging.

### lazyAttrsOf

```nix
type = lib.types.lazyAttrsOf lib.types.str;
```

Like `attrsOf` but evaluates values lazily. Prefer this for large attribute
sets where most entries may never be accessed.

### package

```nix
type = lib.types.package;
```

Accepts a derivation. Conflicting assignments are an error. Use
`mkPackageOption` to declare package options with a sensible default.

## Submodules

The `submodule` type allows an option to contain its own nested set of options.
This is how NixOS models structured configuration like
`services.nginx.virtualHosts`:

```nix
options.services.myapp.backends = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      host = lib.mkOption {
        type    = lib.types.str;
        description = "Backend hostname.";
      };
      port = lib.mkOption {
        type    = lib.types.port;
        default = 80;
        description = "Backend port.";
      };
    };
  });
  default = { };
  description = "Named backend servers.";
};
```

A user configures this as:

```nix
services.myapp.backends = {
  primary   = { host = "10.0.0.1"; port = 8080; };
  secondary = { host = "10.0.0.2"; };
};
```

Each attribute is independently validated against the submodule's options.

### Submodule as a function

When values within a submodule need to be referenced, one can pass a function
instead of an attribute set:

```nix
type = lib.types.submodule ({ config, pkgs, ... }: {
  options = {
    package = lib.mkPackageOption pkgs "nginx" { };
    host = lib.mkOption {
      type    = lib.types.str;
      description = "Backend hostname.";
    };
    configFile = lib.mkOption {
      type     = lib.types.path;
      readOnly = true;
      default = pkgs.writeText "nginx.conf" "... ${config.host} ...";
    };
  };
```

## freeformType

Declaring an explicit option for every possible configuration key is sometimes
impractical — particularly when wrapping an upstream tool that has dozens of
settings, most of which users will never touch. `freeformType` solves this by
letting a submodule accept arbitrary undeclared attributes, merging them
according to a specified type, while still providing typed, documented options
for the settings that matter most.

It is set inside a submodule using a `pkgs.formats` value as the type.
`pkgs.formats` provides ready-made types for common configuration file formats,
and each format's `.type` attribute is suitable for use as a `freeformType`:

```nix
{ config, lib, pkgs, ... }:

let
  settingsFormat = pkgs.formats.json { };
in
{
  options.services.myapp.settings = lib.mkOption {
    type = lib.types.submodule {
      freeformType = settingsFormat.type;

      # Explicitly declared options are still fully typed and documented
      options.port = lib.mkOption {
        type    = lib.types.port;
        default = 8080;
        description = "Port the server listens on.";
      };
    };
    default = { };
    description = "Settings passed directly to myapp's JSON configuration file.";
  };

  config = lib.mkIf config.services.myapp.enable {
    # Serialise the entire settings attrset to JSON — declared and freeform alike
    environment.etc."myapp/config.json".source =
      settingsFormat.generate "myapp-config.json" config.services.myapp.settings;
  };
}
```

A user can then set both declared and arbitrary keys:

```nix
services.myapp.settings = {
  port        = 9000;      # declared option — type-checked
  max_workers = 4;         # undeclared — accepted via freeformType
  log_format  = "json";   # undeclared — accepted via freeformType
};
```

Declared options take precedence and provide type safety and documentation.
Undeclared attributes are merged using `freeformType` and passed through
transparently.

Using `pkgs.formats` is the idiomatic nixpkgs approach because the same format
value that defines the type also provides the `generate` function that
serialises `settings` to the correct file format. The module author does not
need to write a custom serialiser — the format handles both validation and
output. Other available formats include `pkgs.formats.toml`, `pkgs.formats.yaml`,
`pkgs.formats.ini`, and `pkgs.formats.keyValue`.

### Limitations

Freeform attributes cannot reference other options or produce computed values —
they are accepted as-is and merged by the freeform type. If a setting requires
validation or interaction with the rest of the module, declare it as an
explicit option instead.

## Type composition patterns

Types compose freely:

```nix
# Optional list of strings
type = lib.types.nullOr (lib.types.listOf lib.types.str);

# Attribute set of optional ports
type = lib.types.attrsOf (lib.types.nullOr lib.types.port);

# List of structured records
type = lib.types.listOf (lib.types.submodule {
  options = {
    name    = lib.mkOption { type = lib.types.str; };
    enabled = lib.mkOption { type = lib.types.bool; default = true; };
  };
});
```

## Choosing a type

| Situation | Type |
|-----------|------|
| Feature flag | `bool` via `mkEnableOption` |
| Package selection | `package` via `mkPackageOption` |
| Single string, no merging | `str` |
| Multi-contributor string | `lines` |
| Filesystem path | `path` |
| Fixed set of values | `enum [ ... ]` |
| Optional value | `nullOr T` |
| List accumulated from modules | `listOf T` |
| Named records | `attrsOf (submodule ...)` |
| Structured nested config | `submodule { ... }` |
| Settings for config file | `submodule { freeformType = ...; ... }` |
| Arbitrary pass-through | `anything` |
