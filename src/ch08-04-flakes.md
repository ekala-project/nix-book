# Flakes

Flakes are a Nix feature that standardizes how Nix projects declare their
inputs and outputs. They solve two problems at once: pinning (every input is
locked to an exact revision) and discoverability (every flake exposes a
uniform schema of outputs). A flake is just a repository or directory
containing a `flake.nix` file.

Flakes have been available behind an experimental feature flag since 2021 and
remain technically experimental. Despite this status, they have been widely
adopted and are now the dominant way to structure Nix projects. The
"experimental" label reflects ongoing design work rather than instability in
practice. There has been ongoing community debate about the pace of
stabilization, but for new projects flakes are the recommended approach.

## Enabling flakes

Flakes require the `nix-command` and `flakes` experimental features. Add the
following to `/etc/nix/nix.conf` or `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

On NixOS this is done declaratively:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

## The flake.nix structure

A `flake.nix` is a Nix file that returns an attribute set with two required
keys:

```nix
{
  description = "A short description of the flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: {
    # outputs go here
  };
}
```

### inputs

`inputs` declares the flake's dependencies. Each input is fetched and locked
automatically. The most common input is nixpkgs:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
};
```

Input URLs follow the format `github:<owner>/<repo>/<branch-or-commit>`. Other
supported URL schemes include `gitlab:`, `sourcehut:`, `git+https://`, and
plain `path:` references to local directories.

### outputs

`outputs` is a function that receives the evaluated inputs and returns an
attribute set of whatever the flake produces. The argument names must match the
input names:

```nix
outputs = { self, nixpkgs }: {
  packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;
  devShells.x86_64-linux.default = ...;
  nixosConfigurations.myhost = ...;
};
```

The output schema is not strictly enforced, but the Nix tooling recognises
certain well-known attributes:

| Output attribute | Description |
|-----------------|-------------|
| `packages.<system>.<name>` | Buildable packages (`nix build`) |
| `devShells.<system>.<name>` | Development shells (`nix develop`) |
| `apps.<system>.<name>` | Runnable programs (`nix run`) |
| `checks.<system>.<name>` | Test derivations (`nix flake check`) |
| `nixosConfigurations.<name>` | NixOS system configurations |
| `nixosModules.<name>` | Reusable NixOS modules |
| `overlays.<name>` | Nixpkgs overlays |
| `lib` | Library functions |

### Accessing nixpkgs from a flake

Within `outputs`, nixpkgs is accessed through `nixpkgs.legacyPackages`:

```nix
outputs = { self, nixpkgs }:
let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
in
{
  packages.x86_64-linux.mytool = pkgs.callPackage ./mytool.nix { };
};
```

`legacyPackages` exists because the full nixpkgs package set does not fit
neatly into the `packages` output schema (which expects one derivation per
attribute, whereas nixpkgs contains nested sets). It is the standard way to
access nixpkgs packages from a flake output.

To pass `config` or `overlays`, import nixpkgs explicitly:

```nix
pkgs = import nixpkgs {
  system  = "x86_64-linux";
  config  = { allowUnfree = true; };
  overlays = [ self.overlays.default ];
};
```

## flake.lock

When you first run any `nix` command against a flake, Nix resolves all inputs
to their current revisions and writes `flake.lock`:

```json
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1745000000,
        "narHash": "sha256-...",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "a3a3dda3bacf61e8a39258a0ed9c924eeca8e293",
        "type": "github"
      }
    }
  }
}
```

The lockfile pins every input to an exact commit and hash. Commit `flake.lock`
alongside `flake.nix` so that everyone using your repository gets the same
nixpkgs revision.

## Updating pins

```bash
# Update all inputs to their latest revisions
nix flake update

# Update a single input
nix flake update nixpkgs

# Check what changed
git diff flake.lock
```

Updating is an explicit, reviewable operation — a `git diff` on `flake.lock`
shows exactly which commits changed.

## follows

When a flake has multiple inputs that each depend on nixpkgs, you can end up
with several different nixpkgs versions in your closure. The `follows` keyword
redirects an input's dependency to one you control:

```nix
inputs = {
  nixpkgs.url     = "github:NixOS/nixpkgs/nixpkgs-unstable";
  home-manager    = {
    url    = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";  # use our nixpkgs, not home-manager's
  };
};
```

This ensures all inputs share a single nixpkgs version, reducing the number of
packages that need to be built or downloaded.

## Common issues

### Pure evaluation

Flakes are evaluated in pure mode by default: access to `<nixpkgs>` angle
brackets, `builtins.currentSystem`, and impure environment variables is
blocked. Code that relies on these will fail under flakes and needs to be
updated to receive values explicitly through function arguments.

### System argument

Because flakes evaluate purely, `builtins.currentSystem` is unavailable.
Outputs must be defined per-system explicitly, or a helper such as
`flake-utils.lib.eachDefaultSystem` can generate the boilerplate:

```nix
inputs = {
  nixpkgs.url    = "github:NixOS/nixpkgs/nixpkgs-unstable";
  flake-utils.url = "github:numtide/flake-utils";
};

outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.default = pkgs.hello;
    }
  );
```

### Experimental status

Because flakes remain experimental, their interface could change before
stabilization. In practice the core schema has been stable for several years
and breaking changes are unlikely.
