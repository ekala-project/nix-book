# Home-manager

Home-manager is a tool that brings NixOS-style declarative configuration to user environments. It lets you manage your dotfiles, packages, and user-level services using the same module system that NixOS uses for system configuration.

## Why use Home-manager?

### NixOS-like module evaluation at the user level

Home-manager uses the same powerful module system as NixOS (covered in [Chapter 9](./ch09-00-nixos-modules.md)), but for user configuration instead of system configuration. This means you get:

- Type-checked options with validation
- Composable configuration modules
- Documentation built into the system
- The same familiar patterns as NixOS configuration

```nix
# Instead of manually managing dotfiles
programs.git = {
  enable = true;
  userName = "Your Name";
  userEmail = "you@example.com";
  extraConfig = {
    init.defaultBranch = "main";
    pull.rebase = true;
  };
};

# Home-manager generates ~/.gitconfig for you
```

### Separation of user and system requirements

Not everything belongs at the system level. Home-manager lets you:

- Install user-specific tools without requiring root access
- Have different configurations per user on the same system
- Easily sync your environment across multiple machines (NixOS or not)
- Keep user preferences separate from system administration

```nix
# System level (NixOS): infrastructure and shared services
# /etc/nixos/configuration.nix
{
  services.docker.enable = true;
  virtualisation.libvirtd.enable = true;
}

# User level (Home-manager): personal tools and config
# ~/.config/home-manager/home.nix
{
  programs.neovim.enable = true;
  programs.alacritty.enable = true;
  home.packages = with pkgs; [ ripgrep fd bat ];
}
```

### Easier to iterate

Home-manager changes don't affect system state, making experimentation safer and faster:

- **No boot entries**: Changes don't add new bootloader entries like NixOS system rebuilds
- **Faster rollback**: Just `home-manager switch --rollback` to undo
- **No reboot required**: Changes apply immediately to your user session
- **Non-destructive**: Mistakes won't break your system, only your user environment

This makes Home-manager perfect for:
- Testing new programs and configurations
- Learning Nix without system-level risk
- Rapid iteration on your development environment

## Legacy workflow (no flakes)

### Standalone installation

On any Linux distribution or macOS, you can install Home-manager standalone:

```bash
# Add the Home-manager channel
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

# Install Home-manager
nix-shell '<home-manager>' -A install
```

This creates `~/.config/home-manager/home.nix` as your main configuration file.

### Basic configuration

A minimal `home.nix` without flakes:

```nix
{ config, pkgs, ... }:

{
  # Let Home-manager manage itself
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the paths it should manage
  home.username = "yourname";
  home.homeDirectory = "/home/yourname";

  # This value determines the Home Manager release that your configuration is
  # compatible with. Don't change this unless you know what you're doing.
  home.stateVersion = "24.05";

  # Install packages
  home.packages = with pkgs; [
    htop
    ripgrep
    fd
    bat
    jq
  ];

  # Configure programs
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -l";
      gs = "git status";
    };
    bashrcExtra = ''
      export EDITOR=vim
    '';
  };

  programs.vim = {
    enable = true;
    settings = {
      number = true;
      relativenumber = true;
    };
    extraConfig = ''
      set tabstop=2
      set shiftwidth=2
      set expandtab
    '';
  };
}
```

### Activating the configuration

```bash
# Build and activate the new configuration
home-manager switch

# Or build without activating to test
home-manager build

# Rollback to previous generation
home-manager switch --rollback

# List generations
home-manager generations
```

## Using Home-manager with flakes

Flakes provide better dependency management and reproducibility for Home-manager configurations.

### Standalone Home-manager flake

Create `~/.config/home-manager/flake.nix`:

```nix
{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."yourname" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          ./home.nix
        ];
      };
    };
}
```

And `~/.config/home-manager/home.nix`:

```nix
{ config, pkgs, ... }:

{
  home.username = "yourname";
  home.homeDirectory = "/home/yourname";
  home.stateVersion = "24.05";

  # Your configuration here
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
  ];

  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    plugins = with pkgs.vimPlugins; [
      vim-nix
      vim-fugitive
      fzf-vim
    ];
  };
}
```

### Activating with flakes

```bash
# Build and activate
home-manager switch --flake ~/.config/home-manager#yourname

# Or add an alias to your shell
alias hm="home-manager switch --flake ~/.config/home-manager#yourname"

# If you're in ~/.config/home-manager directory, you can also run
home-manager switch --flake .#yourname
```

### Multi-user configuration

A flake can manage multiple users or machines:

```nix
{
  description = "Home Manager configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHome = system: username: modules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = modules;
        };
    in {
      homeConfigurations = {
        # Work laptop
        "alice@worklaptop" = mkHome "x86_64-linux" "alice" [
          ./users/alice/work.nix
          ./modules/development.nix
        ];

        # Personal desktop
        "alice@desktop" = mkHome "x86_64-linux" "alice" [
          ./users/alice/personal.nix
          ./modules/gaming.nix
        ];

        # Server
        "bob@server" = mkHome "x86_64-linux" "bob" [
          ./users/bob/server.nix
        ];
      };
    };
}
```

Activate with:

```bash
home-manager switch --flake .#alice@worklaptop
home-manager switch --flake .#bob@server
```

## Using Home-manager from NixOS modules

On NixOS, you can integrate Home-manager directly into your system configuration. This provides a unified configuration file for both system and user settings.

### Adding Home-manager to NixOS configuration

In your system's `flake.nix`:

```nix
{
  description = "NixOS configuration with Home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix

        # Add Home-manager's NixOS bridge module
        home-manager.nixosModules.home-manager

        # Declare which user you want the home-manager configuration to apply to
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.yourname = import ./home.nix;

          # Optionally, use the system's pkgs in home-manager
          # home-manager.extraSpecialArgs = { inherit inputs; };
        }
      ];
    };
  };
}
```

### Configuration structure

```
/etc/nixos/
├── flake.nix
├── configuration.nix    # System configuration
└── home.nix            # User configuration via Home-manager
```

`configuration.nix` (system level):

```nix
{ config, pkgs, ... }:

{
  # System configuration
  boot.loader.systemd-boot.enable = true;
  networking.hostName = "hostname";

  # Define user account
  users.users.yourname = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  # System services
  services.openssh.enable = true;

  system.stateVersion = "24.05";
}
```

`home.nix` (user level via Home-manager):

```nix
{ config, pkgs, ... }:

{
  # User-specific configuration
  home.stateVersion = "24.05";

  # User packages
  home.packages = with pkgs; [
    firefox
    thunderbird
    vscode
    spotify
  ];

  # User programs
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "docker" "kubectl" ];
    };
  };

  # User services (systemd user units)
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
  };
}
```

### Rebuilding

When using Home-manager as a NixOS module, rebuild the entire system:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#hostname
```

Both system and user configuration changes are applied together.

### Benefits of NixOS integration

1. **Single rebuild command**: No need to run `home-manager switch` separately
2. **Shared state**: Both configs share the same Nix store and garbage collection
3. **Version alignment**: System and user packages stay in sync
4. **Easier maintenance**: One flake.lock for everything

**Note:** If your home-manager configuration is nearly finalized then coupling NixOS and
home-manager concerns may be a maintenance win. However, rapid iteration through
nixos modules can be problematic with things like filling boot/ with NixOS generations.

### Multiple users

You can configure multiple users in the same NixOS configuration:

```nix
{
  description = "NixOS configuration with multiple users";

  outputs = { nixpkgs, home-manager, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          # Configure each user
          home-manager.users.alice = import ./users/alice.nix;
          home-manager.users.bob = import ./users/bob.nix;
        }
      ];
    };
  };
}
```

## Common Home-manager patterns

### Modular configuration

Split your configuration into reusable modules:

```
~/.config/home-manager/
├── flake.nix
├── home.nix              # Main entry point
└── modules/
    ├── git.nix           # Git configuration
    ├── shell.nix         # Shell setup
    ├── neovim.nix        # Neovim config
    └── development.nix   # Development tools
```

`home.nix`:

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./modules/git.nix
    ./modules/shell.nix
    ./modules/neovim.nix
    ./modules/development.nix
  ];

  home.username = "yourname";
  home.homeDirectory = "/home/yourname";
  home.stateVersion = "24.05";
}
```

`modules/git.nix`:

```nix
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";

    aliases = {
      co = "checkout";
      br = "branch";
      ci = "commit";
      st = "status";
      unstage = "reset HEAD --";
    };

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      core.editor = "vim";
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
      };
    };
  };
}
```

### Conditional configuration

Enable features based on the system:

```nix
{ config, pkgs, lib, ... }:

{
  # Linux-specific configuration
  programs.alacritty.enable = lib.mkIf pkgs.stdenv.isLinux true;

  # macOS-specific configuration
  programs.iterm2.enable = lib.mkIf pkgs.stdenv.isDarwin true;
}
```

### Managing dotfiles

Home-manager can manage arbitrary dotfiles:

```nix
{ config, pkgs, ... }:

{
  # Simple file content
  home.file.".config/foo/config.toml".text = ''
    key = "value"
    option = true
  '';

  # Copy from a file in your config directory
  home.file.".config/alacritty/alacritty.yml".source = ./dotfiles/alacritty.yml;

  # Generate from a function
  home.file.".bashrc".text = lib.mkAfter ''
    export PATH=$PATH:$HOME/.local/bin
  '';

  # Symlink entire directory
  home.file.".config/nvim".source = ./config/nvim;
}
```

### XDG directory management

Home-manager has built-in XDG support:

```nix
{ config, pkgs, ... }:

{
  xdg.enable = true;

  # Files go to ~/.config automatically
  xdg.configFile."foo/config.yml".text = ''
    setting: value
  '';

  # Data files go to ~/.local/share
  xdg.dataFile."some-app/data.json".source = ./data.json;

  # User directories
  xdg.userDirs = {
    enable = true;
    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Music";
    pictures = "${config.home.homeDirectory}/Pictures";
    videos = "${config.home.homeDirectory}/Videos";
  };
}
```

## Exploring available options

Home-manager provides hundreds of pre-configured program options. To explore:

```bash
# Search for options
home-manager option programs.git

# Generate documentation
home-manager option | less
```

Popular programs with Home-manager modules include:

- **Shells**: bash, zsh, fish, nushell
- **Editors**: neovim, emacs, vscode
- **Terminals**: alacritty, kitty, wezterm
- **Version control**: git, mercurial
- **Development**: direnv, starship, tmux
- **Desktop**: i3, sway, hyprland, polybar, rofi
- **Services**: gpg-agent, ssh-agent, syncthing

Check the [Home-manager options documentation](https://nix-community.github.io/home-manager/options.html) for the full list.
