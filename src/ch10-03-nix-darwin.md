# nix-darwin

nix-darwin brings NixOS-style declarative configuration to macOS. It provides a module system for managing system settings, packages, and services on macOS using the same patterns you'd use on NixOS.

## Value proposition

### Declarative macOS configuration

NixOS makes the assumption that you're managing Linux + systemd systems declaratively, nix-darwin by comparison exposes macOS + launchd system configuration settings:

- **System settings**: Configure defaults, preferences, keyboard shortcuts
- **Package management**: Install and manage packages through Nix
- **Services**: Manage system and user services (LaunchAgents/LaunchDaemons)
- **Reproducibility**: Same configuration produces the same system state
- **Version control**: Track your system configuration in git

```nix
{
  # Set macOS system preferences
  system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;
  system.defaults.dock.autohide = true;

  # Install packages
  environment.systemPackages = with pkgs; [
    git
    vim
    ripgrep
  ];

  # Enable services
  services.nix-daemon.enable = true;
}
```

### Familiar module system

If you know NixOS, you already know nix-darwin. It uses the same module system (covered in [Chapter 9](./ch09-00-nixos-modules.md)), so concepts like options, config, imports, and merging work identically.

```nix
# Import modules just like NixOS
{
  imports = [
    ./packages.nix
    ./settings.nix
  ];
}
```

### Bridge the gap between NixOS and macOS

For users who work across both platforms:

- Reuse configuration modules between NixOS and nix-darwin
- Share common patterns and tooling
- Leverage the same ecosystem (nixpkgs, Home-manager, etc.)
- Maintain consistency across development environments

## Difference from NixOS modules in nixpkgs

While nix-darwin uses the NixOS module system, it's a separate project from nixpkgs for good reasons:

### Platform-specific concerns

macOS has fundamentally different primitives than Linux:

- **No systemd**: Uses LaunchAgents/LaunchDaemons instead
- **Different filesystem**: APFS instead of ext4/btrfs/etc.
- **macOS-specific APIs**: NSUserDefaults, system preferences
- **Homebrew integration**: Many GUI apps only available via Homebrew Cask
- **System Integrity Protection (SIP)**: Limits what can be modified

```nix
# nix-darwin specific: LaunchDaemons
launchd.daemons.my-service = {
  script = ''
    echo "Running my service"
  '';
  serviceConfig.RunAtLoad = true;
};

# Compare to NixOS: systemd
systemd.services.my-service = {
  script = ''
    echo "Running my service"
  '';
  wantedBy = [ "multi-user.target" ];
};
```

### Separate release cycle

nix-darwin can evolve independently of nixpkgs:

- Faster iteration on macOS-specific features
- No need to wait for NixOS releases
- Can track macOS version changes independently
- Community can contribute macOS-specific modules more easily

### Different scope

NixOS aims to manage the entire operating system. nix-darwin has to work within macOS's constraints:

- Can't replace the kernel or init system
- Can't fully control the boot process
- Must respect SIP and code signing
- Works alongside existing macOS configuration

This means nix-darwin focuses on what it can control:
- Package installation
- User/system preferences (via `defaults`)
- Service management (via launchd)
- Shell environment

## Example usage without flakes

### Installation

```bash
# Install nix-darwin using the installer script
nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
./result/bin/darwin-installer
```

This creates `/etc/nix/darwin-configuration.nix` and sets up the `darwin-rebuild` command.

### Basic configuration

A minimal `/etc/nix/darwin-configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 4;

  # Auto upgrade nix package
  nix.package = pkgs.nix;

  # Enable experimental features
  nix.settings.experimental-features = "nix-command flakes";

  # Install packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    ripgrep
    fd
    bat
    jq
  ];

  # Enable the Nix daemon
  services.nix-daemon.enable = true;

  # macOS system defaults
  system.defaults = {
    # Dock settings
    dock = {
      autohide = true;
      orientation = "bottom";
      show-recents = false;
      tilesize = 48;
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
    };

    # Global macOS settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  # Shell configuration
  programs.bash.enable = true;
  programs.zsh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
  ];
}
```

### Applying configuration

```bash
# Build and activate the new configuration
darwin-rebuild switch

# Build without activating
darwin-rebuild build

# Rollback to previous generation
darwin-rebuild switch --rollback

# List generations
darwin-rebuild --list-generations
```

## Example with flakes

Flakes provide better dependency management and make it easier to version your configuration.

### Creating a nix-darwin flake

Create `/etc/nixos/flake.nix` (or anywhere you prefer):

```nix
{
  description = "Darwin system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager }: {
    darwinConfigurations."hostname" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";  # or "x86_64-darwin" for Intel Macs
      modules = [
        ./configuration.nix
      ];
    };
  };
}
```

### Configuration file

`configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  system.stateVersion = 4;

  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = "nix-command flakes";
      trusted-users = [ "@admin" ];
    };
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
    tmux
    ripgrep
    fd
    bat
    jq
    # macOS-specific tools
    m-cli  # Swiss army knife for macOS
  ];

  services.nix-daemon.enable = true;

  # Homebrew integration for GUI apps
  homebrew = {
    enable = true;
    casks = [
      "firefox"
      "visual-studio-code"
      "spotify"
      "discord"
    ];
    brews = [
      # Command-line tools not in nixpkgs or better via brew
    ];
    taps = [
      "homebrew/cask"
    ];
    # Auto-update Homebrew
    onActivation.autoUpdate = true;
    onActivation.cleanup = "zap";
  };

  # macOS system settings
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "left";
      show-recents = false;
      # Don't rearrange spaces
      mru-spaces = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";  # List view
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      # Disable auto-correct
      NSAutomaticSpellingCorrectionEnabled = false;
      # Faster key repeat
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      # Use dark mode
      AppleInterfaceStyle = "Dark";
      # Expand save panel by default
      NSNavPanelExpandedStateForSaveMode = true;
      # 24-hour time
      AppleICUForce24HourTime = true;
    };

    # Trackpad settings
    trackpad = {
      Clicking = true;  # Tap to click
      TrackpadThreeFingerDrag = true;
    };
  };

  # Shell setup
  programs.zsh.enable = true;
  environment.shells = [ pkgs.bash pkgs.zsh ];

  # Create /etc/zshrc that loads the nix-darwin environment
  programs.zsh.shellInit = ''
    # Nix
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
      . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
  '';

  # User configuration
  users.users.yourname = {
    name = "yourname";
    home = "/Users/yourname";
  };

  # Fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" "Hack" ]; })
    fira-code
    jetbrains-mono
  ];
}
```

### Applying with flakes

```bash
# Build and activate
darwin-rebuild switch --flake /etc/nixos#hostname

# Or from the config directory
cd /etc/nixos
darwin-rebuild switch --flake .#hostname
```

### Integration with Home-manager

Combine nix-darwin with Home-manager for complete system + user configuration:

```nix
{
  description = "Darwin system with Home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager }: {
    darwinConfigurations."hostname" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./configuration.nix

        # Home-manager module
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.yourname = import ./home.nix;
        }
      ];
    };
  };
}
```

Now both system (nix-darwin) and user (Home-manager) configuration apply with a single rebuild:

```bash
darwin-rebuild switch --flake .#hostname
```

## Common issues

### System Integrity Protection (SIP)

SIP prevents modification of certain system files and directories. This can interfere with nix-darwin:

**Problem**: Can't modify `/etc` directly

**Solution**: nix-darwin uses `/etc/static` and symlinks where possible. Some changes require disabling SIP temporarily:

```bash
# Reboot into Recovery Mode (Cmd+R on boot)
# Open Terminal from the Utilities menu
csrutil disable
# Reboot normally
# After nix-darwin setup completes:
# Reboot into Recovery Mode again
csrutil enable
```

Most users don't need to disable SIP anymore, as nix-darwin has workarounds for common cases.

### Homebrew integration

Some GUI applications aren't available in nixpkgs or work better via Homebrew:

**Problem**: Need both Nix and Homebrew packages

**Solution**: Use nix-darwin's Homebrew integration:

```nix
{
  homebrew = {
    enable = true;

    # Formulae (CLI tools)
    brews = [
      "libressl"  # Example: conflicts with openssl in nixpkgs
    ];

    # Casks (GUI apps)
    casks = [
      "google-chrome"
      "slack"
      "docker"
    ];

    # Cleanup old packages on activation
    onActivation.cleanup = "zap";
  };
}
```

This lets nix-darwin manage Homebrew declaratively.

### Shell integration

**Problem**: Shell doesn't load Nix environment

**Solution**: Ensure your shell is configured by nix-darwin:

```nix
{
  programs.zsh.enable = true;  # or programs.bash.enable

  # Make sure Nix is in your PATH
  programs.zsh.shellInit = ''
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
      . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
  '';
}
```

Also set your default shell in System Preferences or via:

```bash
chsh -s /run/current-system/sw/bin/zsh
```

### Activation script failures

**Problem**: `darwin-rebuild switch` fails during activation

**Common causes**:

1. **System preferences locked**: Quit System Preferences before rebuilding
2. **Existing LaunchAgents**: Remove conflicting services manually
3. **Permission issues**: Ensure your user is in the `admin` group

**Solution**: Check the error message carefully. Often it's:

```bash
# Stop conflicting services
launchctl unload ~/Library/LaunchAgents/com.example.service.plist

# Then retry
darwin-rebuild switch --flake .#hostname
```

### Font installation

**Problem**: Fonts installed via nix-darwin don't appear in applications

**Solution**: Fonts are installed to `/run/current-system/sw/share/fonts/`. macOS needs to recognize this directory:

1. nix-darwin should handle this automatically via activation scripts
2. If fonts still don't appear, manually add the directory in Font Book
3. Restart applications that need the fonts

```nix
{
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];
}
```

### Multi-user setup

**Problem**: Need different configurations per user

**Solution**: Combine with Home-manager:

- nix-darwin: System-level settings (dock, defaults, system packages)
- Home-manager: Per-user settings (dotfiles, user packages, user services)

```nix
{
  # System packages (available to all users)
  environment.systemPackages = with pkgs; [ git vim ];

  # Per-user configuration via Home-manager
  home-manager.users.alice = {
    programs.git.userName = "Alice";
  };

  home-manager.users.bob = {
    programs.git.userName = "Bob";
  };
}
```

### Upgrading macOS

**Problem**: After upgrading macOS, nix-darwin stops working

**Solution**: Rebuilding usually fixes issues:

```bash
darwin-rebuild switch --flake .#hostname
```

If that fails:

1. Check nix-darwin issues on GitHub for the new macOS version
2. Update your flake inputs: `nix flake update`
3. Sometimes you need to reinstall the Nix daemon:

```bash
# Uninstall
sudo rm -rf /nix
# Follow official Nix installation for macOS
# Then reinstall nix-darwin
```

### Performance on Apple Silicon

**Problem**: Native ARM packages vs Rosetta

**Solution**: Use `aarch64-darwin` system:

```nix
{
  darwinConfigurations."hostname" = darwin.lib.darwinSystem {
    system = "aarch64-darwin";  # Native Apple Silicon
    # ...
  };
}
```

Most packages in nixpkgs have native aarch64-darwin builds. For packages that don't:

```nix
{
  # Explicitly use x86_64 (Rosetta) for specific packages
  nixpkgs.config.allowUnsupportedSystem = true;

  environment.systemPackages = [
    (pkgs.pkgsx86_64Darwin.somePackage)
  ];
}
```

## Useful nix-darwin options

Browse the full option list:

```bash
# From within your nix-darwin config directory
darwin-option -l | grep system.defaults
```

Or check the [nix-darwin manual](https://daiderd.com/nix-darwin/manual/index.html) online.

Common options to explore:

- `system.defaults.*` - macOS system preferences
- `environment.systemPackages` - System-wide packages
- `homebrew.*` - Homebrew integration
- `services.nix-daemon.*` - Nix daemon settings
- `launchd.*` - LaunchAgents and LaunchDaemons
- `networking.*` - Network configuration
- `security.*` - Security settings
- `users.users.*` - User account management
