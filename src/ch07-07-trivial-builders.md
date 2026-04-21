# Trivial Builders

Not every package requires compiling source code. Nixpkgs provides a set of
"trivial builders" for common cases where you need to wrap a script, write a
small file, or produce a derivation from a simple command. These builders sit
on top of `stdenv.mkDerivation` but expose a much narrower interface, reducing
boilerplate and making intent explicit.

## runCommand

`runCommand` creates a derivation from a single shell command. It is the
simplest way to produce a store path from an arbitrary build step.

```nix
{ runCommand }:

runCommand "my-output" { } ''
  mkdir -p $out
  echo "hello from nix" > $out/hello.txt
''
```

The three arguments are:

1. **name** — the derivation name
2. **env** — an attribute set of environment variables and derivation attributes
3. **buildCommand** — the shell script that produces `$out`

### Passing environment variables

Any attribute in the second argument that is not a recognised derivation
attribute is passed to the build as an environment variable:

```nix
runCommand "greeting" { who = "world"; } ''
  mkdir -p $out
  echo "hello, $who" > $out/greeting.txt
''
```

## writeShellApplication

`writeShellApplication` produces a shell script wrapped with `bash` and
optionally checked with `shellcheck` at build time. It automatically sets
`-euo pipefail` and patches the `PATH` so that referenced packages are
available without absolute paths.

```nix
{ writeShellApplication, curl, jq }:

writeShellApplication {
  name = "fetch-data";

  runtimeInputs = [ curl jq ];

  text = ''
    curl -s "https://api.example.com/data" | jq '.results[]'
  '';
}
```

The resulting derivation installs the script to `$out/bin/<name>`.

### Options

| Attribute | Description |
|-----------|-------------|
| `name` | Name of the script and the produced binary |
| `text` | The body of the shell script |
| `runtimeInputs` | Packages added to `PATH` at runtime |
| `checkPhase` | Override the default shellcheck invocation |
| `excludeShellChecks` | List of shellcheck codes to suppress (e.g. `[ "SC2016" ]`) |
| `meta` | Standard nixpkgs meta attributes |


## writeShellScript and writeShellScriptBin

When you need a script but do not want shellcheck or the automatic `PATH`
rewriting that `writeShellApplication` provides, use `writeShellScript` or
`writeShellScriptBin`.

`writeShellScript` writes the script to `$out` directly:

```nix
{ writeShellScript }:

writeShellScript "my-hook" ''
  echo "running hook"
  exec "$@"
''
```

`writeShellScriptBin` places it at `$out/bin/<name>`, matching the layout
expected by `buildEnv` and similar tools:

```nix
{ writeShellScriptBin }:

writeShellScriptBin "greet" ''
  echo "hello, ''${1:-world}"
''
```

The difference from `writeShellApplication` is that these do not rewrite
`PATH`, do not enforce `set -euo pipefail`, and do not run shellcheck.

## writePython3Bin

`writePython3Bin` produces a Python 3 script installed to `$out/bin/<name>`.
The interpreter is patched in at build time so the script is fully
self-contained in the Nix store.

```nix
{ writePython3Bin, python3Packages }:

writePython3Bin "check-yaml" {
  libraries = [ python3Packages.pyyaml ];
} ''
  import sys
  import yaml

  with open(sys.argv[1]) as f:
      data = yaml.safe_load(f)
  print(f"Loaded {len(data)} top-level keys")
''
```

The three arguments are:

1. **name** — the binary name
2. **options** — an attribute set; `libraries` lists Python packages to make available
3. **text** — the Python source

### writePython3

`writePython3` is the same but writes the script directly to `$out` rather
than `$out/bin/<name>`:

```nix
writePython3 "helper.py" {
  libraries = [ python3Packages.requests ];
} ''
  import requests
  print(requests.get("https://example.com").status_code)
''
```

## writeText and writeTextFile

`writeText` creates a plain text file in the Nix store. It is one of the
simplest builders and is useful for configuration files, templates, or any
static text content.

```nix
{ writeText }:

writeText "config.json" ''
  {
    "debug": false,
    "port": 8080
  }
''
```

This produces a store path like `/nix/store/…-config.json` containing exactly
the provided text.

`writeTextFile` is the underlying function and accepts an attribute set with
more options:

```nix
{ writeTextFile }:

writeTextFile {
  name = "my-config";
  text = "key=value";
  destination = "/etc/myapp/config";  # path inside $out
  executable = false;
  checkPhase = ''
    grep -q "key" $out/etc/myapp/config
  '';
}
```

| Attribute | Description |
|-----------|-------------|
| `name` | Derivation name |
| `text` | File contents |
| `destination` | Path inside `$out` (default: `$out`) |
| `executable` | Whether to set the executable bit |
| `checkPhase` | Optional validation script |
| `meta` | Standard nixpkgs meta attributes |

### writeTextDir

`writeTextDir` is a convenience wrapper that places the text file at a
specified path within `$out`:

```nix
writeTextDir "share/myapp/config.toml" ''
  [server]
  port = 8080
''
```

The result is a derivation whose `$out/share/myapp/config.toml` contains the
text. This layout works well with `symlinkJoin` or `buildEnv` when assembling
packages from multiple pieces.

## symlinkJoin

`symlinkJoin` merges multiple derivations into a single store path by creating
symlinks. This is useful for combining a program with extra files, or for
assembling a custom environment from several packages.

```nix
{ symlinkJoin, hello, writeTextDir }:

symlinkJoin {
  name = "hello-with-config";
  paths = [
    hello
    (writeTextDir "share/hello/config" "greeting=hi")
  ];
}
```

### Adding wrappers

A common pattern is to use `symlinkJoin` together with `makeWrapper` to
produce a wrapped binary:

```nix
{ symlinkJoin, hello, makeWrapper }:

symlinkJoin {
  name = "hello-wrapped";
  paths = [ hello ];
  buildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/hello \
      --set GREETING "hi"
  '';
}
```

## buildEnv

`buildEnv` creates a single store path that merges a set of packages by
symlinking their contents. It is similar to `symlinkJoin` but offers more
control over conflict resolution and is the mechanism behind `nix-env` profile
generations.

```nix
{ buildEnv, git, vim, ripgrep }:

buildEnv {
  name = "my-tools";
  paths = [ git vim ripgrep ];
}
```

### Options

| Attribute | Description |
|-----------|-------------|
| `name` | Derivation name |
| `paths` | List of derivations to merge |
| `pathsToLink` | Subdirectories to include (default: everything) |
| `extraOutputsToInstall` | Extra package outputs to link in (e.g. `[ "dev" "man" ]`) |
| `ignoreCollisions` | If `true`, silently ignore conflicting files (default: `false`) |
| `postBuild` | Shell commands to run after the environment is assembled |

### Linking only specific subdirectories

`pathsToLink` restricts which directories are symlinked. This keeps the
resulting environment lean when you only need binaries, for example:

```nix
buildEnv {
  name = "bin-only";
  paths = [ git vim ripgrep ];
  pathsToLink = [ "/bin" ];
}
```

### Handling collisions

By default, `buildEnv` will throw an error if two packages provide the same
path. Set `ignoreCollisions = true` to suppress this, taking the first match:

```nix
buildEnv {
  name = "permissive-env";
  paths = [ packageA packageB ];
  ignoreCollisions = true;
}
```

### Including extra outputs

Packages can have multiple outputs (see the multiple outputs chapter). By
default only the default output is linked. Use `extraOutputsToInstall` to pull
in additional ones:

```nix
buildEnv {
  name = "dev-env";
  paths = [ openssl zlib ];
  extraOutputsToInstall = [ "dev" ];
}
```

This is useful when building a development environment where you need headers
alongside libraries.

### buildEnv vs symlinkJoin

`buildEnv` and `symlinkJoin` are closely related. The main practical
differences are:

- `buildEnv` supports `pathsToLink`, `extraOutputsToInstall`, and
  `ignoreCollisions`; `symlinkJoin` does not
- `symlinkJoin` supports a `postBuild` hook and accepts `buildInputs` for
  tools like `makeWrapper`; `buildEnv` also has `postBuild` but is more
  commonly used for pure path merging

For simple merging, either works. Prefer `buildEnv` when you need fine-grained
control over which directories are linked or when assembling user environments.
Prefer `symlinkJoin` when you need to run `wrapProgram` or other post-assembly
steps.

## Choosing the right builder

| Use case | Builder |
|----------|---------|
| Arbitrary build step producing `$out` | `runCommand` |
| Shell script with runtime dependencies | `writeShellApplication` |
| Shell script without PATH rewriting | `writeShellScriptBin` |
| Python script | `writePython3Bin` |
| Static text file | `writeText` / `writeTextFile` |
| Text file at a specific path | `writeTextDir` |
| Merge derivations with collision control | `buildEnv` |
| Merge derivations with post-build wrapping | `symlinkJoin` |

Trivial builders are often the right tool when you need to glue packages
together, wrap upstream software with configuration, or produce small utilities
without a full build system. Because they share the same `$out` convention as
any other Nix derivation, the results compose naturally with the rest of
nixpkgs.
