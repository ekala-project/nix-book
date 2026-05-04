# Using Flakes

This chapter covers practical workflows for using flakes in real-world projects. For the basics of what flakes are and their structure, see [Chapter 8.4](./ch08-04-flakes.md).

## Creating and structuring flakes

### Simple example

A minimal flake for a single package:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.default = pkgs.callPackage ./default.nix { };

      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [ pkgs.nodejs ];
      };
    };
}
```

This works if you only need to support one system. For most projects, you'll want multi-system support.

### Moderate example using genAttrs

To support multiple systems, use `genAttrs` to avoid repetition:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.callPackage ./default.nix { };
          tool-a = pkgs.callPackage ./tool-a.nix { };
          tool-b = pkgs.callPackage ./tool-b.nix { };
        }
      );

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs
              nodePackages.typescript
              nodePackages.prettier
            ];
          };
        }
      );
    };
}
```

`forAllSystems` is a helper that maps over each system, calling the function with the system string. The result is:

```nix
{
  packages = {
    x86_64-linux = { default = ...; tool-a = ...; tool-b = ...; };
    aarch64-linux = { default = ...; tool-a = ...; tool-b = ...; };
    x86_64-darwin = { default = ...; tool-a = ...; tool-b = ...; };
    aarch64-darwin = { default = ...; tool-a = ...; tool-b = ...; };
  };
  devShells = { ... };
}
```

## Updating pins and lock files

### Basic update workflow

```bash
# Update all inputs to their latest versions
nix flake update

# Update a specific input
nix flake update nixpkgs

# Check what changed
git diff flake.lock
```

The `flake.lock` diff shows exactly which commits changed, making updates reviewable and safe to roll back.

### Updating to a specific version

You can override an input temporarily without modifying `flake.nix`:

```bash
# Use a specific nixpkgs revision
nix build --override-input nixpkgs github:NixOS/nixpkgs/abc123

# Use a local path
nix develop --override-input nixpkgs path:/home/user/nixpkgs
```

To permanently change an input to a specific revision:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/abc123def456";  # full commit hash
  # or
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";   # branch or tag
};
```

Then run `nix flake update nixpkgs` to update the lockfile.

### Using `follows` to deduplicate inputs

When your flake has multiple inputs that themselves depend on nixpkgs, you can end up with several different nixpkgs versions in your dependency graph. The `follows` directive tells an input to use your nixpkgs instead of its own:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, agenix }: {
    # Now everything uses the same nixpkgs
  };
}
```

Without `follows`, each dependency might use a different nixpkgs revision, leading to:
- Longer evaluation (each package needs to instantiate a separate nixpkgs instance)
- Larger disk usage (multiple versions of the same packages)
- Potentially longer build times (can't reuse cached builds)

You can inspect your flake's dependency graph:

```bash
nix flake metadata
```

This shows all inputs and their dependencies, making it easy to spot duplicate nixpkgs versions.

### Common criticisms: Law of Demeter violations

A common criticism of flakes is that they encourage violations of the Law of Demeter (also known as the principle of least knowledge). The `follows` mechanism requires you to know about your dependencies' dependencies:

```nix
# You need to know that home-manager depends on nixpkgs internally
home-manager.inputs.nixpkgs.follows = "nixpkgs";

# And that it might have other inputs you want to override
home-manager.inputs.utils.follows = "flake-utils";
```

This creates tight coupling: if `home-manager` changes its internal dependencies, your flake might break or need updates. You're forced to care about implementation details of your dependencies.

The alternative would be for dependencies to accept pkgs as a parameter:

```nix
# Hypothetical cleaner API
outputs = { self, nixpkgs, home-manager }:
  home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    # ...
  };
```

Some newer flake libraries are moving toward this pattern to avoid unnecessary instantation. But the only way to get rid of featching the extra inputs still relies heavily on `follows`.

## Common flake patterns and templates

### Multi-system support with flake-utils

Instead of manually handling multiple systems with `genAttrs`, `flake-utils` provides helpers:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.default = pkgs.hello;

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.git pkgs.vim ];
        };
      }
    ) // {
      overlays.default = ./overlay.nix;
    };
}
```

`eachDefaultSystem` generates outputs for common systems automatically. Other useful functions:

- `eachSystem [ "x86_64-linux" ]` - specific systems only
- `mkApp` - helper for creating `apps` outputs
- `flattenTree` - convert nested attribute sets to flat packages
- "System agnostic" outputs such as overlays need to be outside of the `eachDefaultSystem` call.

### Modular flakes with flake-parts

For larger projects, `flake-parts` provides a module system for organizing flakes:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages.default = pkgs.hello;

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.nodejs ];
        };
      };

      flake = {
        # Non-per-system outputs
        nixosModules.default = ./module.nix;
      };
    };
}
```

Benefits of flake-parts:

1. **Automatic per-system handling**: No need for `genAttrs` or manual system loops
2. **Module composition**: Split your flake into multiple files
3. **Type checking**: Better error messages for malformed outputs
4. **Extensibility**: Third-party modules can add new output types

Example multi-file structure:

```nix
# flake.nix
{
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./packages.nix
        ./devshells.nix
        ./nixos.nix
      ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
    };
}

# packages.nix
{ perSystem = { pkgs, ... }: {
  packages = {
    tool-a = pkgs.callPackage ./tool-a { };
    tool-b = pkgs.callPackage ./tool-b { };
  };
}; }

# devshells.nix
{ perSystem = { pkgs, ... }: {
  devShells.default = pkgs.mkShell {
    packages = with pkgs; [ git nodejs ];
  };
}; }
```

**Note:** This strongly couples your project to flake evaluation, and makes it difficult for non-flakes to use your project. If your the leaf consumer or only expect to support flake usage then this is not an issue.

## Development environments with flakes

### Basic development shell

```nix
{
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              python313Packages.pip
              python313Packages.virtualenv
            ];

            shellHook = ''
              echo "Python development environment"
              python --version
            '';
          };
        }
      );
    };
}
```

Enter the shell with:

```bash
nix develop
```

### Multiple development shells

You can define multiple named shells for different workflows:

```nix
{
  devShells = forAllSystems (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [ nodejs nodePackages.typescript ];
      };

      ci = pkgs.mkShell {
        packages = with pkgs; [ nodejs nodePackages.typescript docker ];
      };

      docs = pkgs.mkShell {
        packages = with pkgs; [ mdbook ];
      };
    }
  );
}
```

Use them with:

```bash
nix develop         # uses 'default'
nix develop .#ci
nix develop .#docs
```

### Integration with direnv

See [Chapter 10.6](./ch10-06-direnv.md) for automatic shell activation when entering a directory.

## CI/CD integration

### GitHub Actions

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: cachix/install-nix-action@v22
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - uses: cachix/cachix-action@v12
        with:
          name: my-cache
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'

      - name: Build
        run: nix build

      - name: Run tests
        run: nix flake check
```

### GitLab CI

```yaml
build:
  image: nixos/nix:latest
  before_script:
    - echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
  script:
    - nix build
    - nix flake check
```

### Flake checks

Define checks in your flake that run in CI:

```nix
{
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          formatting = pkgs.runCommand "check-formatting" {} ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${self}
            touch $out
          '';

          tests = pkgs.runCommand "run-tests" {} ''
            ${self.packages.${system}.default}/bin/mytool test
            touch $out
          '';
        }
      );
    };
}
```

Run all checks with:

```bash
nix flake check
```

This is perfect for CI: a single command that validates your entire project.

## Common mistakes

### Not committing flake.lock

The lockfile must be committed to ensure reproducibility. Without it, different users and CI runs may get different dependency versions.

```bash
# Always commit both files together
git add flake.nix flake.lock
git commit -m "Update dependencies"
```

### Using mutable references without understanding

Avoid branches in input URLs unless you understand the implications:

```nix
# This URL references a branch, which is mutable
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

# This URL references a branch and a commit, which is immutable. `rev` needs to be updated for `flake update` to fetch new content
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable&rev=abcd...";
```

The branch reference itself is mutable, but `flake.lock` pins it to a specific commit. The danger is when someone runs `nix flake update` without reviewing changes—sudden breakage can occur if the branch moved to an incompatible revision.

Always review `git diff flake.lock` after updates.

### Forgetting to update system attributes

When adding new outputs, remember to handle all systems:

```nix
# Wrong: only works on x86_64-linux
packages.x86_64-linux.mytool = ...;

# Right: use a helper to cover all systems
packages = forAllSystems (system: {
  mytool = ...;
});
```

**Note:** This is a common criticism of flakes, that there are many potentially supported systems which are artifically pruned by this as it acts also as a system filter.

### Circular follows

Don't create circular dependencies with follows:

```nix
# Bad: creates a cycle
inputs = {
  a.url = "github:foo/a";
  b.url = "github:foo/b";
  a.inputs.b.follows = "b";
  b.inputs.a.follows = "a";  # circular!
};
```

Nix will error on circular follows during evaluation.

### Mixing pure and impure evaluation

Code that works outside flakes might fail in pure evaluation mode:

```nix
# Fails in flakes: <nixpkgs> is not available
let pkgs = import <nixpkgs> {};

# Fails in flakes: currentSystem is not available in pure mode
builtins.currentSystem

# Fails in flakes: environment variables are not available
builtins.getEnv "HOME"
```

Always pass values explicitly through function parameters in flakes.

**Note:** You can pass `--impure` to enable those features against, however this is discouraged as your flake evaluation is no longer hermetic.

### Introducing the flake paradigm unnecessarily

Flakes work best as an **entrypoint** to your project. They should define inputs, outputs, and how to build things—but the actual build logic should live in regular Nix files that can be imported with or without flakes.

**Good pattern:**

```nix
# flake.nix - just the entrypoint
{
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.callPackage ./default.nix { };
        }
      );
    };
}

# default.nix - regular Nix, no flake knowledge
{ stdenv, fetchurl }:
stdenv.mkDerivation {
  name = "mytool";
  src = fetchurl { ... };
  # ...
}
```

This keeps `default.nix` reusable in non-flake contexts (like nixpkgs itself).

**Bad pattern:**

```nix
# flake.nix
{
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system: {
        default = self.lib.buildTool {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
        };
      });
    };

  # Flake-specific helper function
  lib.buildTool = { system, pkgs }: ...;
}
```

Now your build logic is locked inside the flake and can't be easily imported elsewhere.

## Making flakes enjoyable

### Keep inputs minimal

Every input is a dependency that needs updating and potentially causes version conflicts. Only add inputs you actually need:

```nix
# Minimal - just nixpkgs
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

# Too many - do you really need all these?
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  flake-utils.url = "github:numtide/flake-utils";
  flake-compat.url = "github:edolstra/flake-compat";
  pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  # ... and so on
};
```

Often you can achieve the same result with a simple helper function instead of adding a dependency:

```nix
# Instead of flake-utils
let
  systems = [ "x86_64-linux" "aarch64-linux" ];
  forAllSystems = nixpkgs.lib.genAttrs systems;
in
  # use forAllSystems...
```

### Treat flakes as an entrypoint

As mentioned above, keep your flake.nix thin. It should primarily:
1. Declare inputs
2. Wire up outputs
3. Delegate to regular Nix files for actual logic

This makes your code more reusable and easier to test outside the flake context.

### Use follows liberally

When you do add inputs, always check if they depend on nixpkgs and add follows:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

This prevents dependency version explosion and keeps builds fast.

## Project templates

Nix provides templates to quickly scaffold new flake projects:

```bash
# List available templates
nix flake show templates

# Create a new project from a template
nix flake init -t templates#rust

# Or use a template from any flake
nix flake init -t github:user/repo#template-name
```

You can create your own templates in your flake:

```nix
{
  outputs = { self }: {
    templates.rust-project = {
      path = ./templates/rust;
      description = "A Rust project with Nix flake";
    };
  };
}
```
