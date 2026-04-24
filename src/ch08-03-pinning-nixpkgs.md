# Pinning Nixpkgs

When you write `import <nixpkgs> {}`, the version of nixpkgs you get depends
on whatever channel happens to be installed on the machine at the time. Two
developers running the same expression on different days, or on different
machines, may get different packages. Builds stop being reproducible.

Pinning solves this by recording an exact nixpkgs revision — a specific Git
commit — alongside your code. Anyone who checks out your repository gets the
same nixpkgs, regardless of what channels they have configured.

## Avoid pkgs fetchers for pinning

It may be tempting to pin nixpkgs using a fetcher from the package set itself,
such as `pkgs.fetchFromGitHub`. This is strongly discouraged. Package set
fetchers are derivations — they are built during the build phase, not during
evaluation. Using one to fetch nixpkgs means nixpkgs cannot be imported until
that derivation has been built, which forces Nix to perform a build in the
middle of evaluation. This is called Import From Derivation (IFD) and it
significantly increases evaluation time, prevents some evaluation optimisations,
and can break tooling that assumes evaluation is pure. See the [Nix manual
section on IFD](https://nix.dev/manual/nix/stable/language/import-from-derivation)
for a full explanation.

Conceptually, you would also need to import nixpkgs to be able to use its build
time fetchers, so you now just importing multiple nixpkgs' unnecessarily.

Always use `builtins` fetchers or a pinning tool for nixpkgs itself. The
`builtins` fetchers run at evaluation time and do not introduce IFD.

## Pinning with fetchTarball

The simplest approach that requires no external tooling is `builtins.fetchTarball`.
GitHub exposes a tarball of any commit, and `builtins.fetchTarball` verifies it
against a hash:

```nix
let
  nixpkgs = builtins.fetchTarball {
    url    = "https://github.com/NixOS/nixpkgs/archive/a3a3dda3bacf61e8a39258a0ed9c924eeca8e293.tar.gz";
    sha256 = "0zb9sic985plq8mfs7sfibgbjapzqqxnqzzcsk41fnfxn0bh2qmv";
  };
  pkgs = import nixpkgs { };
in
pkgs.hello
```

The `sha256` hash ensures the tarball has not changed. If it does not match,
evaluation fails immediately. To get the hash for a new commit, set it to an
empty string and let Nix report the correct value:

```nix
sha256 = "";  # Nix will print the correct hash and fail
```

To update the pin, replace the commit in `url` with the new one and update the
hash.

## Pinning tools

Managing `fetchTarball` pins by hand becomes tedious across multiple inputs.
Several tools exist to automate this:

### npins

`npins` is a minimal, file-based pinning tool. It stores pins in a
`npins/` directory and generates a `npins/default.nix` you can import:

```bash
# Initialise npins in a new project
npins init

# Add nixpkgs at a specific branch
npins add github NixOS nixpkgs --branch nixpkgs-unstable

# Update all pins to their latest commits
npins update

# Update a single pin
npins update nixpkgs
```

```nix
# default.nix
let
  sources = import ./npins;
  pkgs    = import sources.nixpkgs { };
in
pkgs.hello
```

## Flakes

Flakes handle pinning natively through `flake.lock`, which records the exact
revision of every input. This is covered in full in the next section, but if
you are starting a new project and are comfortable enabling experimental
features, flakes are the most integrated pinning solution available.

## Choosing an approach

| Approach | Requires | Best for |
|----------|----------|----------|
| `fetchTarball` | Nothing | Single input, minimal dependencies |
| `npins` / `niv` (deprecated) | The tool installed | Multiple inputs, no flakes |
| Flakes | `nix` with experimental features | New projects, full reproducibility |

The key property all three share is that the pin is a file committed to your
repository. Updating nixpkgs becomes an explicit, reviewable change rather than
a silent side effect of `nix-channel --update`.
