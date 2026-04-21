# Options

Options are the public interface of a module. They declare what can be
configured, what type of value is expected, what the default is, and how the
option is described in the documentation. A module that only sets `config`
without declaring options is valid, but modules that expose options allow
other modules and users to interact with them in a controlled way.

## Declaring an option

Options are declared under the `options` key using `lib.mkOption`:

```nix
{ lib, ... }:

{
  options.services.myapp.enable = lib.mkOption {
    type    = lib.types.bool;
    default = false;
    description = "Whether to enable myapp.";
  };
}
```

The path under `options` becomes the path users set in their configuration:

```nix
services.myapp.enable = true;
```

## mkOption arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `type` | yes | The option type (see the Option Types chapter) |
| `default` | no | Value used when the option is not set |
| `defaultText` | no | Human-readable description of the default, for documentation |
| `example` | no | Example value shown in the manual |
| `description` | no | Markdown description rendered in the manual |
| `internal` | no | If `true`, hide from generated documentation |
| `visible` | no | If `false`, hide from generated documentation |
| `readOnly` | no | If `true`, disallow assignments from outside the declaring module |
| `apply` | no | Function applied to the final value before it is exposed in `config` |

## mkEnableOption

A boolean enable option is so common that nixpkgs provides a shorthand:

```nix
options.services.myapp.enable = lib.mkEnableOption "myapp";
```

This is equivalent to:

```nix
options.services.myapp.enable = lib.mkOption {
  type    = lib.types.bool;
  default = false;
  description = "Whether to enable myapp.";
};
```

## mkPackageOption

Similarly, `mkPackageOption` declares a package option with a sensible default
drawn from `pkgs`:

```nix
options.services.myapp.package = lib.mkPackageOption pkgs "myapp" { };
```

This produces an option of type `lib.types.package` defaulting to
`pkgs.myapp`. An optional `default` override can be provided:

```nix
options.services.myapp.package = lib.mkPackageOption pkgs "myapp" {
  default = [ "myapp" "full" ];  # pkgs.myapp.full
};
```

## Grouping options with submodules

Related options are conventionally nested under a common prefix. The full path
to an option is just the attribute path from the top of `options`:

```nix
options.services.myapp = {
  enable  = lib.mkEnableOption "myapp";
  package = lib.mkPackageOption pkgs "myapp" { };

  port = lib.mkOption {
    type    = lib.types.port;
    default = 8080;
    description = "Port myapp listens on.";
  };

  dataDir = lib.mkOption {
    type    = lib.types.path;
    default = "/var/lib/myapp";
    description = "Directory for myapp state.";
  };
};
```

Users then configure the service as a coherent group:

```nix
services.myapp = {
  enable  = true;
  port    = 9000;
  dataDir = "/srv/myapp";
};
```

## The apply argument

`apply` transforms the final merged value before it is exposed in `config`.
This is useful for normalisation or for converting a user-friendly type into
an internal representation:

```nix
options.services.myapp.logLevel = lib.mkOption {
  type    = lib.types.enum [ "debug" "info" "warn" "error" ];
  default = "info";
  apply   = lib.toUpper;  # config.services.myapp.logLevel will be "INFO"
};
```

The transformation is invisible to callers — they set the option as usual and
receive the transformed value when reading `config`.

## readOnly options

Marking an option `readOnly` prevents assignments from anywhere other than the
module that declared it. This is useful for computed values that should be
observable but not overridden:

```nix
options.services.myapp.configFile = lib.mkOption {
  type     = lib.types.path;
  readOnly = true;
  description = "Path to the generated configuration file (read-only).";
};

config.services.myapp.configFile = pkgs.writeText "myapp.conf" "...";
```

Any attempt by another module to assign `services.myapp.configFile` will
produce an evaluation error.
