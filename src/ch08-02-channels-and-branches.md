# Channels and Branches

"Channel" is an overloaded term in the Nix ecosystem. It refers to two related
but distinct things: the legacy `nix-channel` mechanism for subscribing to a
nixpkgs feed, and the release branches that those feeds track. Understanding
both is useful because the branch names appear everywhere — in flake inputs, in
pinning tools, and in documentation — regardless of whether you use the legacy
channel mechanism at all.

## Release branches

Nixpkgs is developed on a rolling `master` branch and periodically stabilised
into versioned release branches. The main branches you will encounter are:

| Branch | Tracks | Character |
|--------|--------|-----------|
| `nixpkgs-unstable` | `master` | Rolling, latest packages, occasional breakage |
| `nixos-unstable` | `master` | Same as above, extra NixOS-specific CI |
| `nixos-YY.MM` | Stable release (e.g. `nixos-24.11`) | Stable, security backports only |
| `nixpkgs-YY.MM-darwin` | Stable release, Darwin builds | Stable, gated on macOS CI passing |

NixOS stable releases follow a `YY.MM` scheme and are cut twice a year, in May
and November. Once a release branch is cut, it receives only security and
critical bug fixes — package versions are frozen.

### nixpkgs-unstable vs nixos-unstable

Both branches track `master` but are bumped independently by Hydra, the NixOS
build infrastructure. A branch is only advanced once all of its required builds
succeed, so either branch may lag behind `master` by hours or days.

The practical difference is that `nixos-unstable` requires additional NixOS
system-level tests to pass before advancing, which means it can lag behind
`nixpkgs-unstable` but offers slightly higher confidence for NixOS
configurations. For non-NixOS workflows — development shells, macOS, WSL —
`nixpkgs-unstable` is preferred.

## The legacy nix-channel mechanism

Before flakes and pinning tools, `nix-channel` was how users subscribed to a
nixpkgs branch. It works by pointing at a URL that Hydra keeps updated to the
latest successful build of a branch:

```
https://nixos.org/channels/nixos-unstable
https://nixos.org/channels/nixos-24.11
```

Managing channels looks like this:

```bash
# Subscribe to a channel
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs

# Download the latest version of all subscribed channels
nix-channel --update

# List current channels
nix-channel --list
```

After an update, `<nixpkgs>` in Nix expressions resolves to the downloaded
channel. The major drawback is that `nix-channel --update` silently changes
the version of nixpkgs used by every expression on the machine, making builds
non-reproducible between updates. For this reason, channels have largely been
superseded by explicit pinning and flakes, which are covered in the following
sections.

## Choosing a branch

**Unstable** (`nixpkgs-unstable` or `nixos-unstable`) is the right choice when
you want the latest package versions and are comfortable with occasional
breakage. It is the most popular choice among individual developers and is
generally more stable in practice than its name suggests, since Hydra gates
advancement on CI passing.

**Stable** (`nixos-24.11`, etc.) is the right choice when predictability
matters more than freshness — production servers, shared developer environments,
or anywhere that an unexpected package update would be disruptive.

Mixing both is also possible and common: pin most of your configuration to a
stable branch, then selectively pull individual packages from unstable when you
need a newer version.
