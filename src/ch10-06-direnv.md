# direnv

direnv is a tool that automatically loads and unloads environment variables when you enter or leave a directory. Combined with nix-direnv, it provides automatic activation of Nix development shells with caching for improved performance.

## Why use direnv?

### Automatic shell activation

Without direnv, you need to manually enter development environments:

```bash
cd my-project
nix develop  # or nix-shell
# Now you're in the environment
# ...work...
exit  # Leave the environment
```

This manual activation becomes tedious when switching between projects frequently. direnv solves this by automatically loading the environment when you `cd` into a directory:

```bash
cd my-project
# Environment automatically activated!
# All tools and dependencies are available

cd ..
# Environment automatically unloaded
```

### Fast re-activation with caching

Standard `nix develop` re-evaluates the flake every time you enter a directory, which can take several seconds. nix-direnv caches the built environment, making subsequent activations nearly instantaneous:

```bash
# First activation: builds and caches
cd my-project
# direnv: loading ~/my-project/.envrc
# direnv: using flake
# [... Nix evaluation and building ...]
# direnv: export +SOME_VAR +ANOTHER_VAR ...

# Leave and re-enter
cd .. && cd my-project
# direnv: loading ~/my-project/.envrc
# direnv: using flake
# [Instant! Uses cached environment]
# direnv: export +SOME_VAR +ANOTHER_VAR ...
```

This makes switching between projects feel instantaneous rather than waiting for Nix evaluation each time.

### Per-project environments

direnv keeps project environments isolated and automatically managed:

- Different projects can use different tool versions
- Environment variables are project-specific
- No global pollution of your shell environment
- Share `.envrc` files with teammates for consistent environments

### Integration with editors and IDEs

Many editors integrate with direnv:

- VSCode (via extensions)
- Emacs (via direnv-mode)
- Vim/Neovim (via direnv.vim)
- JetBrains IDEs (via plugins)

These integrations ensure your editor sees the same environment as your terminal, making language servers and tools work correctly.

## Installation

Install direnv and nix-direnv through your system configuration or Home-manager.

### NixOS system-wide

```nix
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
```

### Home-manager

```nix
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # For bash
  programs.bash.enable = true;

  # Or for zsh
  programs.zsh.enable = true;
}
```

### Manual installation

If not using NixOS or Home-manager:

```bash
# Install packages
nix-env -iA nixpkgs.direnv nixpkgs.nix-direnv

# Add to your shell's rc file (~/.bashrc, ~/.zshrc, etc.)
eval "$(direnv hook bash)"  # or zsh, fish, etc.
```

## Legacy example (no flakes)

For projects using traditional `shell.nix` or `default.nix` files, create a `.envrc` file in your project root:

```bash
# .envrc
use nix
```

Then allow direnv to load it:

```bash
direnv allow
```

### Example shell.nix

```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    nodejs
    nodePackages.typescript
    nodePackages.prettier
  ];

  shellHook = ''
    echo "Node.js development environment"
    node --version
  '';
}
```

Now when you `cd` into the directory:

```bash
cd my-project
# direnv: loading ~/my-project/.envrc
# direnv: using nix
# Node.js development environment
# v20.11.0
# direnv: export +AR +AS +CC ...
```

The environment is active and all tools are available.

### Setting environment variables

You can set project-specific environment variables in `.envrc`:

```bash
# .envrc
use nix

# Set environment variables
export DATABASE_URL="postgresql://localhost/mydb"
export DEBUG=true
export API_KEY="dev-key-123"
```

These variables are automatically set when entering the directory and unset when leaving.

### Using a specific nixpkgs version

For reproducibility, pin nixpkgs in `.envrc`:

```bash
# .envrc
use nix -p https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz
```

Or reference a specific `shell.nix`:

```bash
# .envrc
use nix shell.nix
```

## Flake example

For projects using flakes, direnv integrates seamlessly with `nix develop`.

### Basic flake setup

Create a `.envrc` file:

```bash
# .envrc
use flake
```

And a `flake.nix`:

```nix
{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              python311
              python311Packages.pip
              python311Packages.virtualenv
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

Allow direnv:

```bash
direnv allow
```

When you enter the directory, the flake environment activates automatically:

```bash
cd my-project
# direnv: loading ~/my-project/.envrc
# direnv: using flake
# Python development environment
# Python 3.11.7
# direnv: export +AR +AS +CC ...
```

### Multiple development shells

If your flake defines multiple devShells, specify which one to use:

```nix
{
  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      devShells.x86_64-linux = {
        default = pkgs.mkShell {
          packages = [ pkgs.nodejs ];
        };

        ci = pkgs.mkShell {
          packages = [ pkgs.nodejs pkgs.docker ];
        };

        docs = pkgs.mkShell {
          packages = [ pkgs.mdbook ];
        };
      };
    };
}
```

Select a specific shell in `.envrc`:

```bash
# .envrc
use flake .#ci
```

### Custom environment variables in flakes

Set variables in the devShell:

```nix
{
  devShells.default = pkgs.mkShell {
    packages = [ pkgs.nodejs ];

    # Environment variables
    NODE_ENV = "development";
    DATABASE_URL = "postgresql://localhost/mydb";

    shellHook = ''
      export DEBUG=true
      echo "Development environment loaded"
    '';
  };
}
```

Or combine with `.envrc`:

```bash
# .envrc
use flake

# Additional variables not in flake
export LOCAL_CONFIG="/path/to/local/config"
export MACHINE_SPECIFIC_VAR="some-value"
```

This pattern keeps machine-specific or secret configuration out of version control while maintaining reproducible environments in the flake.

### Flake with inputs

Reference other flakes or tools:

```nix
{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { nixpkgs, rust-overlay, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.rust-bin.stable.latest.default
          pkgs.rust-analyzer
        ];
      };
    };
}
```

direnv handles all the complexity of flake evaluation and caching automatically.

## Common issues

### Permission denied or .envrc blocked

When you first create or modify a `.envrc` file, direnv blocks it for security. You'll see:

```
direnv: error /home/user/project/.envrc is blocked. Run `direnv allow` to approve its content
```

This prevents malicious code from automatically executing. Review the `.envrc` contents, then approve it:

```bash
direnv allow
```

You need to run `direnv allow` again whenever `.envrc` changes.

### Slow activation on first load

The first time direnv loads a flake, it needs to evaluate and build the environment, which can take time:

```bash
cd my-project
# direnv: loading .envrc
# [... several seconds of Nix evaluation ...]
# direnv: export +AR +AS ...
```

This is expected. Subsequent activations use the cached environment and are nearly instant. If you update `flake.nix` or `flake.lock`, direnv detects the change and rebuilds the cache.

### direnv not loading automatically

If direnv doesn't activate when entering a directory, check that the hook is installed. Run this in your shell:

```bash
direnv --version
```

If direnv isn't found or the hook isn't loaded, you're missing the shell integration. Add to your `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(direnv hook bash)"  # or zsh, fish, etc.
```

Then restart your shell or source the config file:

```bash
source ~/.bashrc  # or ~/.zshrc
```

### Environment variables not set

If environment variables from `.envrc` or the devShell aren't available, verify direnv loaded successfully:

```bash
direnv status
```

This shows what `.envrc` is currently loaded and any errors. You can also manually reload:

```bash
direnv reload
```

### Flake evaluation errors

If your flake has syntax errors or evaluation issues, direnv shows the error:

```bash
cd my-project
# direnv: loading .envrc
# direnv: using flake
# error: attribute 'devShells' missing
# ...
```

Fix the errors in your `flake.nix` and direnv automatically retries when you save the file.

### Old environment persists

Sometimes direnv caches get stale or corrupted. Clear the cache for a project:

```bash
# From within the project directory
direnv reload
```

Or clear all direnv caches:

```bash
# Warning, this removes allow previously allowed directories as well
rm -rf ~/.local/share/direnv/allow/*
```

Then re-allow your `.envrc` files.

### Conflicts with manual nix-shell

Running `nix-shell` or `nix develop` manually while direnv is active can cause environment conflicts. When direnv is managing the environment, avoid manual shell commands. If you need a different shell temporarily, disable direnv first:

```bash
direnv deny .
nix develop
# ...work in manual shell...
exit
direnv allow .
```

### Editor not seeing environment

Some editors don't automatically pick up direnv environments. Check for direnv plugins or extensions:

- **VSCode**: Install "direnv" extension
- **Vim/Neovim**: Install direnv.vim
- **Emacs**: Use direnv-mode package

After installing, restart your editor. It should now load the direnv environment for the project.

### Performance issues with large projects

In very large projects, direnv can slow down shell prompts if it checks status too frequently. You can configure direnv to be less aggressive:

```bash
# Add to ~/.config/direnv/direnvrc or ~/.direnvrc
export DIRENV_LOG_FORMAT=""  # Reduce logging
```

Or disable direnv checking on every prompt and manually reload when needed:

```bash
# In .envrc, use manual reload
watch_file flake.nix flake.lock
```

This tells direnv to only reload when specific files change.

## Advanced patterns

### Combining multiple .envrc files

You can load a parent `.envrc` and extend it:

```bash
# .envrc in subdirectory
source_up  # Load parent .envrc if it exists
use flake

export SUBPROJECT_VAR="value"
```

### Custom use functions

Create reusable direnv functions in `~/.config/direnv/direnvrc`:

```bash
# ~/.config/direnv/direnvrc

use_python() {
  layout python python3.11
}

use_node() {
  local node_version="${1:-20}"
  export PATH="$PWD/node_modules/.bin:$PATH"
}
```

Then use them in `.envrc`:

```bash
# .envrc
use_python
use_node 18
```

### Layering with local configuration

Keep secrets and machine-specific config separate:

```bash
# .envrc (committed to git)
use flake

# Source local config if it exists (not in git)
[[ -f .envrc.local ]] && source_env .envrc.local
```

```bash
# .envrc.local (in .gitignore)
export DATABASE_PASSWORD="secret"
export AWS_PROFILE="personal"
```

This pattern lets you share `.envrc` while keeping sensitive data private.

### Integration with Docker

Use direnv alongside Docker for local development:

```bash
# .envrc
use flake

# Set Docker environment
export COMPOSE_PROJECT_NAME="myproject"
export DOCKER_BUILDKIT=1
```

The environment is automatically configured when entering the project directory, making `docker-compose` commands consistent.

## Best practices

### Commit .envrc to version control

Include `.envrc` in git so teammates get the same environment setup. Add `.envrc.local` to `.gitignore` for machine-specific overrides.

### Use flakes for reproducibility

Flakes provide better reproducibility than `shell.nix` with channels. The `flake.lock` pins all dependencies, ensuring everyone gets identical environments.

### Keep .envrc simple

Prefer putting complex logic in `flake.nix` or `shell.nix` rather than `.envrc`. The `.envrc` should primarily just activate the Nix environment:

```bash
# Good: simple and clear
use flake

# Less good: complex logic in .envrc
use flake
if [ -d "$HOME/custom-tools" ]; then
  export PATH="$HOME/custom-tools:$PATH"
fi
# ... more complexity ...
```

### Document requirements

Add a README note about direnv for new contributors:

```markdown
## Development Setup

This project uses direnv for automatic environment management.

1. Install direnv: https://direnv.net/docs/installation.html
2. Run `direnv allow` in the project directory
3. The environment activates automatically when you cd into the directory
```

### Use watch_file for cache invalidation

Tell direnv to reload when specific files change:

```bash
# .envrc
use flake

# Reload if these files change
watch_file flake.nix     # Default for `use flake`
watch_file flake.lock    # Default for `use flake`
watch_file package.json  # For projects with multiple config files
```

This ensures the cache stays in sync with your configuration.

## Further reading

- [direnv documentation](https://direnv.net/)
- [nix-direnv GitHub](https://github.com/nix-community/nix-direnv)
- [Nix flakes and direnv](https://nixos.wiki/wiki/Flakes#Direnv_integration)

direnv transforms Nix development environments from something you manually enter to seamless, automatic project context that "just works" as you navigate your filesystem.
