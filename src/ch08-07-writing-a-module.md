# Writing a Module

This chapter brings together everything covered so far by working through the
construction of a complete NixOS module. We will write a module for a
hypothetical service called `myapp` — a simple HTTP server — covering option
declaration, conditional configuration, systemd integration, and user/group
management.

## The anatomy of a service module

Most NixOS service modules follow a predictable structure:

1. Declare options under `services.<name>`
2. Gate all configuration behind `mkIf config.services.<name>.enable`
3. Create a dedicated user and group
4. Write a configuration file from option values
5. Define a systemd service unit

## Step 1: declare options

```nix
# myapp.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.myapp;
in
{
  options.services.myapp = {
    enable = lib.mkEnableOption "myapp HTTP server";

    package = lib.mkPackageOption pkgs "myapp" { };

    port = lib.mkOption {
      type    = lib.types.port;
      default = 8080;
      description = "Port the server listens on.";
    };

    dataDir = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/myapp";
      description = "Directory for persistent data.";
    };

    logLevel = lib.mkOption {
      type    = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log verbosity.";
    };

    extraConfig = lib.mkOption {
      type    = lib.types.lines;
      default = "";
      description = "Additional lines appended to the configuration file.";
    };
  };
```

Binding `cfg = config.services.myapp` at the top of the `let` block avoids
repeating the full path throughout the module and is standard practice in
nixpkgs.

## Step 2: gate config behind mkIf

```nix
  config = lib.mkIf cfg.enable {
    # everything below only applies when myapp is enabled
  };
}
```

All of the following steps go inside this `mkIf` block.

## Step 3: user and group

Dedicated system users improve security by limiting the privileges of the
service process:

```nix
    users.users.myapp = {
      isSystemUser = true;
      group        = "myapp";
      home         = cfg.dataDir;
      description  = "myapp service user";
    };

    users.groups.myapp = { };
```

## Step 4: generate a configuration file

Use `pkgs.writeText` or a template to produce the configuration file in the
Nix store, then reference it from the service unit:

```nix
    environment.etc."myapp/myapp.conf".text = ''
      port      = ${toString cfg.port}
      data_dir  = ${cfg.dataDir}
      log_level = ${cfg.logLevel}

      ${cfg.extraConfig}
    '';
```

For larger or more structured configuration files, `pkgs.writeTextFile` or a
format-specific generator (such as `pkgs.formats.toml`) can be more
appropriate.

## Step 5: systemd service

```nix
    systemd.services.myapp = {
      description = "myapp HTTP server";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];

      serviceConfig = {
        ExecStart     = "${cfg.package}/bin/myapp --config /etc/myapp/myapp.conf";
        User          = "myapp";
        Group         = "myapp";
        Restart       = "on-failure";
        RestartSec    = "5s";

        # Hardening
        NoNewPrivileges      = true;
        ProtectSystem        = "strict";
        ProtectHome          = true;
        ReadWritePaths       = [ cfg.dataDir ];
        PrivateTmp           = true;
      };
    };
```

## Step 6: assertions and firewall

Add assertions to catch configuration mistakes early, and optionally open the
firewall:

```nix
    assertions = [
      {
        assertion = cfg.port > 1024 || config.users.users.myapp.isSystemUser == false;
        message   = "myapp: ports below 1024 require running as root, which is not recommended.";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf
      config.networking.firewall.enable
      (lib.mkDefault [ cfg.port ]);
```

## The complete module

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.myapp;
in
{
  options.services.myapp = {
    enable  = lib.mkEnableOption "myapp HTTP server";
    package = lib.mkPackageOption pkgs "myapp" { };

    port = lib.mkOption {
      type    = lib.types.port;
      default = 8080;
      description = "Port the server listens on.";
    };

    dataDir = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/myapp";
      description = "Directory for persistent data.";
    };

    logLevel = lib.mkOption {
      type    = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log verbosity.";
    };

    extraConfig = lib.mkOption {
      type    = lib.types.lines;
      default = "";
      description = "Additional lines appended to the configuration file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.port > 1024;
        message   = "myapp: use a port above 1024 to avoid running as root.";
      }
    ];

    users.users.myapp = {
      isSystemUser = true;
      group        = "myapp";
      home         = cfg.dataDir;
      description  = "myapp service user";
    };

    users.groups.myapp = { };

    environment.etc."myapp/myapp.conf".text = ''
      port      = ${toString cfg.port}
      data_dir  = ${cfg.dataDir}
      log_level = ${cfg.logLevel}

      ${cfg.extraConfig}
    '';

    systemd.services.myapp = {
      description = "myapp HTTP server";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];

      serviceConfig = {
        ExecStart        = "${cfg.package}/bin/myapp --config /etc/myapp/myapp.conf";
        User             = "myapp";
        Group            = "myapp";
        Restart          = "on-failure";
        RestartSec       = "5s";
        NoNewPrivileges  = true;
        ProtectSystem    = "strict";
        ProtectHome      = true;
        ReadWritePaths   = [ cfg.dataDir ];
        PrivateTmp       = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkDefault [ cfg.port ];
  };
}
```

## Using the module

Import the module and enable the service:

```nix
# configuration.nix
{ ... }:

{
  imports = [ ./myapp.nix ];

  services.myapp = {
    enable   = true;
    port     = 9000;
    logLevel = "debug";
    extraConfig = ''
      max_connections = 100
    '';
  };
}
```

## Common patterns

### Passing secrets

Avoid putting secrets in the Nix store. Instead, reference a file path that
will be present at runtime:

```nix
options.services.myapp.secretKeyFile = lib.mkOption {
  type    = lib.types.path;
  example = "/run/secrets/myapp-key";
  description = "Path to a file containing the secret key.";
};
```

Then load it in the service unit:

```nix
serviceConfig.EnvironmentFile = cfg.secretKeyFile;
```

### Multiple instances

Use `attrsOf (submodule ...)` to allow multiple named instances of a service,
following the pattern used by `services.nginx.virtualHosts` and
`services.postgresql.ensureDatabases`.

### Exposing the generated config path

If other modules need to reference the generated configuration file:

```nix
options.services.myapp.configFile = lib.mkOption {
  type     = lib.types.path;
  readOnly = true;
  description = "Path to the generated configuration file.";
};

config.services.myapp.configFile = "/etc/myapp/myapp.conf";
```
