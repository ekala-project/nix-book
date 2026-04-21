# Testing Modules

NixOS includes a purpose-built testing framework that runs complete virtual
machines, applies a NixOS configuration, and runs assertions against the live
system. These are called NixOS tests (or VM tests). They are the standard way
to verify that a module's configuration actually produces the intended system
behaviour.

## How NixOS tests work

A NixOS test is a Nix expression that describes one or more virtual machines
and a Python test script. The framework:

1. Builds a NixOS system closure for each machine
2. Starts the machines in QEMU
3. Runs the Python script, which can interact with each machine via a serial
   console and check the system state
4. Passes or fails based on assertions in the script

Tests are run with `nix build` or `nix-build` and produce a log. Because the
machines are fully isolated from the host, tests are reproducible and can be
run in CI without special privileges.

## A minimal test

```nix
# test.nix
{ pkgs ? import <nixpkgs> { } }:

pkgs.nixosTest {
  name = "myapp-test";

  nodes.machine = { ... }: {
    imports = [ ./myapp.nix ];
    services.myapp.enable = true;
  };

  testScript = ''
    machine.wait_for_unit("myapp.service")
    machine.wait_for_open_port(8080)
    response = machine.succeed("curl -s http://localhost:8080/health")
    assert "ok" in response, f"unexpected response: {response}"
  '';
}
```

Run with:

```
nix-build test.nix
```

## nodes

The `nodes` attribute is an attribute set of machine definitions. Each value
is a NixOS module. Single-machine tests typically use `nodes.machine`; the
name is arbitrary.

```nix
nodes = {
  server = { ... }: {
    services.myapp.enable = true;
  };

  client = { ... }: {
    environment.systemPackages = [ pkgs.curl ];
  };
};
```

Each machine is independently addressable from the test script by name.

## The test script

The test script is a Python program. The framework provides one global
variable per machine, named after the node. Common methods:

| Method | Description |
|--------|-------------|
| `machine.start()` | Start the VM (done automatically) |
| `machine.wait_for_unit(unit)` | Block until the systemd unit is active |
| `machine.wait_for_open_port(port)` | Block until a TCP port accepts connections |
| `machine.succeed(cmd)` | Run a shell command, assert exit 0, return stdout |
| `machine.fail(cmd)` | Run a shell command, assert non-zero exit |
| `machine.execute(cmd)` | Run a shell command, return (exit_code, stdout) |
| `machine.copy_from_host(src, dst)` | Copy a file from the host into the VM |
| `machine.wait_until_succeeds(cmd)` | Retry cmd until it exits 0 |
| `machine.wait_until_fails(cmd)` | Retry cmd until it exits non-zero |
| `machine.shutdown()` | Shut down the VM |

### Multi-machine scripts

In a multi-machine test, each node is a separate Python variable:

```python
server.wait_for_unit("myapp.service")
client.wait_until_succeeds("curl -s http://server:8080/health | grep ok")
```

Machine hostnames default to the node name, so `server` and `client` resolve
correctly inside the virtual network.

## Interactive testing

During development it is useful to drop into the test environment
interactively:

```
nix run .#checks.x86_64-linux.myapp-test.driverInteractive
```

Or with the legacy interface:

```
$(nix-build test.nix -A driverInteractive)/bin/nixos-test-driver
```

This starts the Python REPL with the machine variables available. You can call
`machine.start()` and then interact with the VM manually, which is helpful for
debugging failing assertions.

## Testing option defaults and types

For modules with complex option interactions, it can be worth testing that
defaults are correct and that invalid values are rejected. The latter requires
checking that evaluation fails:

```nix
testScript = ''
  # Verify the default port is in use
  machine.wait_for_open_port(8080)

  # Verify a custom port works
'';

nodes.custom = { ... }: {
  imports = [ ./myapp.nix ];
  services.myapp = {
    enable = true;
    port   = 9000;
  };
};
```

Evaluation failures (wrong types, failed assertions) can be tested using
`pkgs.testers.testEqualContents` or by building a configuration that is
expected to fail with `nix-instantiate --eval`.

## Putting tests in a flake

When using flakes, expose tests as checks so they run with `nix flake check`:

```nix
# flake.nix
{
  outputs = { self, nixpkgs }: {
    checks.x86_64-linux.myapp = nixpkgs.legacyPackages.x86_64-linux.nixosTest {
      name = "myapp";

      nodes.machine = { ... }: {
        imports = [ self.nixosModules.myapp ];
        services.myapp.enable = true;
      };

      testScript = ''
        machine.wait_for_unit("myapp.service")
        machine.wait_for_open_port(8080)
      '';
    };

    nixosModules.myapp = import ./myapp.nix;
  };
}
```

Run all checks with:

```
nix flake check
```

## Tips for writing reliable tests

- Use `wait_for_unit` rather than `sleep` — it is both faster and more robust
- Use `wait_until_succeeds` for external readiness checks (HTTP, database
  connections) rather than waiting for the unit, since a unit can be active
  before it is ready to serve requests
- Keep test VMs lean: only enable the services under test to keep build times
  short
- Test failure cases too: assert that disabling a service really stops it and
  closes its port
- Store test helpers in a shared Python snippet if multiple tests repeat the
  same setup steps
