# Deployment Tools

Deploying NixOS systems, especially across multiple machines or remote environments, requires specialized tooling beyond the built-in `nixos-rebuild` command. Several community tools have emerged to handle remote deployment, bare-metal provisioning, and fleet management scenarios.

## deploy-rs

deploy-rs is a specialized tool for deploying NixOS configurations to remote systems. When you need to manage multiple NixOS machines from a central configuration repository, `nixos-rebuild --target-host` becomes cumbersome and lacks features like rollback handling and health checks. deploy-rs provides declarative remote deployment with built-in safety features.

### How deploy-rs works

Unlike `nixos-rebuild`, which operates primarily on the local system, deploy-rs builds configurations locally (or in CI) and then pushes them to remote systems. This approach means:

- Build time doesn't impact the target machine
- Multiple systems can be deployed in parallel
- Failed builds never affect running systems
- You control exactly when activation happens

The tool connects to remote systems via SSH, copies the closure, and activates the new configuration with optional health checks and automatic rollback.

### Basic setup

Install deploy-rs in your development environment and configure it in your flake. The configuration declares which systems to deploy and how to reach them:

```nix
{
  description = "NixOS fleet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { nixpkgs, deploy-rs, ... }: {
    nixosConfigurations = {
      webserver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/webserver/configuration.nix ];
      };

      database = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/database/configuration.nix ];
      };
    };

    deploy.nodes = {
      webserver = {
        hostname = "web.example.com";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos
            self.nixosConfigurations.webserver;
        };
      };

      database = {
        hostname = "db.example.com";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos
            self.nixosConfigurations.database;
        };
      };
    };
  };
}
```

Deploy to all systems:

```bash
deploy
```

Deploy to a specific system:

```bash
deploy .#webserver
```

### SSH configuration

deploy-rs uses SSH for remote access, so proper SSH configuration is essential. Ensure you have SSH key-based authentication set up:

```bash
# Copy your SSH key to the remote system
ssh-copy-id root@web.example.com

# Test connection
ssh root@web.example.com
```

For systems behind firewalls or jump hosts, configure SSH in `~/.ssh/config`:

```
Host webserver
  HostName web.example.com
  User root
  IdentityFile ~/.ssh/deploy_key

Host database
  HostName db.example.com
  User root
  ProxyJump jumphost.example.com
```

Then reference the SSH config name in your deploy configuration:

```nix
{
  deploy.nodes.webserver = {
    hostname = "webserver";  # Uses ~/.ssh/config
    profiles.system = {
      # ...
    };
  };
}
```

### Health checks and rollback

One of deploy-rs's key features is automatic rollback when deployments fail. Add health checks to verify the system is working after activation:

```nix
{
  deploy.nodes.webserver = {
    hostname = "web.example.com";
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.x86_64-linux.activate.nixos
        self.nixosConfigurations.webserver;

      # Auto-rollback settings
      autoRollback = true;
      magicRollback = true;

      # Custom activation script
      activate = {
        custom = ''
          # Wait for web server to start
          timeout 30 bash -c 'until curl -f http://localhost:80; do sleep 1; done'
        '';
      };
    };
  };
}
```

If the health check fails or the SSH connection drops during activation, deploy-rs automatically rolls back to the previous configuration.

### Multi-profile deployments

Beyond system profiles, deploy-rs supports deploying multiple profiles to a single machine. This is useful for separating concerns like system configuration and user environments:

```nix
{
  deploy.nodes.webserver = {
    hostname = "web.example.com";

    profiles = {
      system = {
        user = "root";
        path = deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.webserver;
      };

      user-alice = {
        user = "alice";
        path = deploy-rs.lib.x86_64-linux.activate.home-manager
          self.homeConfigurations.alice;
      };
    };
  };
}
```

Deploy specific profiles:

```bash
deploy .#webserver.system     # Deploy only system profile
deploy .#webserver.user-alice # Deploy only user profile
```

### Remote building

By default, deploy-rs builds configurations locally. For systems with different architectures or when building on constrained machines, use remote builders:

```nix
{
  deploy.nodes.raspberry-pi = {
    hostname = "rpi.local";
    profiles.system = {
      user = "root";
      remoteBuild = true;  # Build on the target system
      path = deploy-rs.lib.aarch64-linux.activate.nixos
        self.nixosConfigurations.raspberry-pi;
    };
  };
}
```

Or configure distributed builds in your local `nix.conf`:

```
builders = ssh://builder@build-server.example.com aarch64-linux
```

### Integration with CI/CD

deploy-rs works well in CI/CD pipelines. Build and test configurations in CI, then deploy automatically:

```yaml
# GitHub Actions example
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: cachix/install-nix-action@v22
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Build configurations
        run: nix build .#nixosConfigurations.webserver.config.system.build.toplevel

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

      - name: Deploy
        run: nix run github:serokell/deploy-rs -- --skip-checks
```

The `--skip-checks` flag bypasses some deploy-rs validation checks that may not work in CI environments.

## nixos-anywhere

nixos-anywhere is a tool for installing NixOS on bare-metal servers remotely, without needing physical access or pre-installed operating systems. When you provision new servers from hosting providers, they typically boot with a generic Linux installation image. nixos-anywhere can transform these systems into NixOS with your configuration, all over SSH.

### How nixos-anywhere works

The tool uses a multi-stage process:

1. Boots the target machine into a minimal Linux environment (kexec)
2. Partitions disks according to your disko configuration
3. Installs NixOS with your configuration
4. Reboots into the new NixOS system

This entire process happens remotely without requiring console access, bootable USBs, or custom installation media.

### Prerequisites

You need:

- A server with an existing Linux installation (most hosting providers offer Ubuntu, Debian, etc.)
- SSH access to that server
- A NixOS configuration for the target system
- A disko configuration for disk partitioning

### Basic usage

First, create your NixOS configuration and disko layout:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  };

  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./configuration.nix
        ./disk-config.nix
      ];
    };
  };
}
```

```nix
# disk-config.nix
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
          };
          ESP = {
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
```

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "myserver";
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3... your-key-here"
  ];

  system.stateVersion = "24.05";
}
```

Install NixOS on the remote system:

```bash
nixos-anywhere --flake .#myserver root@existing-server.example.com
```

The tool connects via SSH, kexecs into a NixOS installer environment, partitions the disk, installs your configuration, and reboots into NixOS.

### SSH key management

nixos-anywhere needs SSH access both to the initial Linux system and to the final NixOS installation. During installation, it temporarily allows root login to copy the system closure. After installation completes, your NixOS configuration's SSH settings take over.

Ensure your configuration includes your SSH key:

```nix
{
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxx your-key"
  ];

  # Or create a regular user
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxx your-key"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
}
```

### Handling different providers

Different hosting providers have different quirks. Some common scenarios:

**Hetzner Cloud:**
```bash
# Hetzner requires --kexec parameter
nixos-anywhere --flake .#myserver --kexec https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz root@hetzner-ip
```

**DigitalOcean:**
```bash
# Works with standard Ubuntu droplet
nixos-anywhere --flake .#myserver root@droplet-ip
```

**Custom cloud providers:**

Some providers don't support kexec or have restricted kernels. In these cases, you might need to:

1. Boot from rescue mode
2. Use the provider's custom kernel
3. Manually partition before running nixos-anywhere

Check the nixos-anywhere documentation for provider-specific guides.

### Encrypted disk setup

nixos-anywhere works with disko's encrypted disk configurations. The installation process needs to handle disk encryption setup:

```nix
# disk-config.nix with encryption
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
          };
          ESP = {
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              passwordFile = "/tmp/disk-password.txt";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
```

Provide the password during installation:

```bash
echo "my-secure-password" > /tmp/disk-password.txt
nixos-anywhere --flake .#myserver --disk-encryption-keys /tmp/disk-password.txt root@server-ip
rm /tmp/disk-password.txt
```

After installation, you'll need to configure remote unlocking (via SSH in initrd) or physical access for boot.

### Debugging failed installations

When installations fail, nixos-anywhere leaves the system in the kexec environment, allowing you to debug. SSH into the system and check logs:

```bash
ssh root@server-ip

# Check disko output
journalctl -u disko

# Manually inspect partitions
lsblk
fdisk -l

# Try manual disko run
disko-install --flake /path/to/flake#myserver
```

Common failure points include:

- Incorrect disk device names (`/dev/sda` vs `/dev/vda` vs `/dev/nvme0n1`)
- Insufficient disk space
- UEFI vs BIOS boot configuration mismatches
- Network connectivity issues during installation

## nixos-rebuild for simple remote deployment

Before reaching for specialized tools, consider that `nixos-rebuild` itself supports remote deployment for simple scenarios:

```bash
nixos-rebuild switch --target-host root@server.example.com --flake .#myserver
```

This builds the configuration locally and activates it remotely. It's suitable when you:

- Manage a small number of systems
- Don't need advanced rollback features
- Want minimal tooling overhead

For fleet management or production deployments, deploy-rs provides more safety features.

## Other deployment tools

### colmena

colmena is another NixOS deployment tool with a focus on parallel deployment and declarative configuration. It's similar to deploy-rs but with different design choices:

```nix
# hive.nix
{
  meta = {
    nixpkgs = import <nixpkgs> {};
  };

  webserver = { name, nodes, ... }: {
    deployment = {
      targetHost = "web.example.com";
      targetUser = "root";
    };

    imports = [ ./hosts/webserver/configuration.nix ];
  };

  database = { name, nodes, ... }: {
    deployment = {
      targetHost = "db.example.com";
      targetUser = "root";
    };

    imports = [ ./hosts/database/configuration.nix ];
  };
}
```

Deploy with:

```bash
colmena apply
```

colmena excels at parallel deployment to many systems and provides introspection commands for checking configuration differences before deployment.

### morph

morph predates many modern deployment tools but remains stable and straightforward:

```nix
# network.nix
{
  network = {
    description = "My network";
  };

  webserver = { config, pkgs, ... }: {
    deployment.targetHost = "web.example.com";
    imports = [ ./hosts/webserver/configuration.nix ];
  };
}
```

Deploy with:

```bash
morph deploy network.nix switch
```

morph is simpler than deploy-rs but lacks some modern features like automatic rollback.

## Best practices

### Version control everything

All deployment configurations should live in version control:

```
my-fleet/
├── flake.nix
├── flake.lock
├── hosts/
│   ├── webserver/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── database/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
├── modules/
│   └── common/
│       └── default.nix
└── README.md
```

This enables:

- Audit trails for all changes
- Rollback to previous configurations
- Collaborative configuration management
- Deployment from CI/CD

### Test deployments in staging

Always test configuration changes in a staging environment before deploying to production:

```nix
{
  deploy.nodes = {
    webserver-staging = {
      hostname = "web-staging.example.com";
      profiles.system = {
        path = deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.webserver;
      };
    };

    webserver-production = {
      hostname = "web.example.com";
      profiles.system = {
        path = deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.webserver;
      };
    };
  };
}
```

Deploy to staging first:

```bash
deploy .#webserver-staging
# Verify everything works
deploy .#webserver-production
```

### Use health checks

Always configure health checks for critical services:

```nix
{
  deploy.nodes.webserver = {
    profiles.system = {
      autoRollback = true;
      magicRollback = true;

      activate.custom = ''
        # Wait for web server
        timeout 60 bash -c 'until curl -f http://localhost:80/health; do sleep 2; done'

        # Check database connectivity
        systemctl is-active postgresql.service

        # Verify critical paths
        test -f /var/lib/important/data
      '';
    };
  };
}
```

This prevents broken deployments from staying active.

### Automate secret deployment

Combine deployment tools with secret management:

```nix
{
  # Using agenix
  age.secrets.database-password = {
    file = ./secrets/db-password.age;
    owner = "postgres";
  };

  services.postgresql = {
    enable = true;
    authentication = ''
      host all all 0.0.0.0/0 password
    '';
  };

  # Password is automatically decrypted on deployment
}
```

Secrets are encrypted in the repository and only decrypted on target systems.

### Document deployment procedures

Maintain a deployment runbook:

```markdown
# Deployment Guide

## Prerequisites
- SSH access to all systems
- Configured SSH keys
- Access to secrets repository

## Deploy to staging
```bash
deploy .#webserver-staging
```

## Deploy to production
```bash
# 1. Test staging first
curl https://web-staging.example.com/health

# 2. Deploy to production
deploy .#webserver-production

# 3. Verify deployment
curl https://web.example.com/health

# 4. Monitor logs
ssh root@web.example.com journalctl -fu nginx
```

## Rollback procedure
```bash
ssh root@web.example.com
nixos-rebuild --rollback switch
```
```

This ensures consistent deployment processes across team members.

### Monitor deployment status

Track deployment history and system state:

```bash
# Check current generation
nixos-rebuild list-generations

# View system configuration
nixos-option system.stateVersion

# Check services
systemctl status

# Review recent logs
journalctl -b
```

Consider integrating with monitoring tools to track deployment success rates and system health.

## Common issues

### SSH connection failures during deployment

When deploy-rs or nixos-rebuild can't connect to remote systems, SSH configuration is usually the culprit. Verify basic connectivity first:

```bash
ssh root@server.example.com echo "Connection works"
```

If this fails, check:

- SSH keys are properly installed on the remote system
- SSH agent has the key loaded: `ssh-add -l`
- Firewall rules allow SSH connections
- DNS resolves correctly: `dig server.example.com`

For systems behind jump hosts, ensure your SSH config has proper `ProxyJump` configuration.

### Build failures with different architectures

Deploying ARM systems from x86_64 machines requires cross-compilation or remote builders. When you see "unsupported platform" errors, configure distributed building:

```nix
# On your local system
{
  nix.buildMachines = [{
    hostName = "aarch64-builder.example.com";
    sshUser = "builder";
    system = "aarch64-linux";
    maxJobs = 4;
    speedFactor = 2;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  }];

  nix.distributedBuilds = true;
  nix.extraOptions = ''
    builders-use-substitutes = true
  '';
}
```

Or use deploy-rs's `remoteBuild` option to build on the target system.

### Rollback failures

Automatic rollback sometimes fails if the system is in a broken state that prevents rollback activation. When this happens, you need manual intervention:

```bash
# SSH into the system
ssh root@server.example.com

# List available generations
nixos-rebuild list-generations

# Manually switch to previous generation
nixos-rebuild --rollback switch

# If that fails, use the bootloader entry
reboot
# Select previous generation from bootloader menu
```

For critical systems, consider keeping a rescue USB or console access available.

### nixos-anywhere disk detection issues

Different hosting providers use different disk naming schemes (`/dev/sda`, `/dev/vda`, `/dev/nvme0n1`). When nixos-anywhere fails with disk errors, SSH into the existing system and check:

```bash
lsblk
fdisk -l
```

Update your disko configuration to match the actual disk device name:

```nix
{
  disko.devices.disk.main = {
    device = "/dev/vda";  # Match actual device
    # ...
  };
}
```

### Network configuration after nixos-anywhere install

After nixos-anywhere installs NixOS, the network configuration from your flake takes over. If you lose connectivity, it's usually because the NixOS configuration doesn't match the server's network setup. Ensure your configuration enables DHCP or uses the correct static IP:

```nix
{
  networking = {
    useDHCP = true;
    # Or static configuration
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.1.10";
      prefixLength = 24;
    }];
    defaultGateway = "192.168.1.1";
    nameservers = [ "8.8.8.8" "8.8.4.4" ];
  };
}
```

Most cloud providers support DHCP, but bare-metal servers may require static configuration.

### Permission errors during activation

When deploy-rs fails with permission errors during activation, the deployment user lacks necessary privileges. Either deploy as root:

```nix
{
  deploy.nodes.webserver = {
    profiles.system = {
      user = "root";
      # ...
    };
  };
}
```

Or configure sudo for passwordless system activation:

```nix
{
  security.sudo.wheelNeedsPassword = false;

  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "..." ];
  };
}
```

### Parallel deployment timeouts

When deploying to many systems simultaneously, some deployments may timeout. Adjust timeout settings in deploy-rs:

```nix
{
  deploy.nodes.webserver = {
    profiles.system = {
      # Increase timeout for slow builds
      timeout = 600;  # 10 minutes instead of default
      # ...
    };
  };
}
```

Or deploy in smaller batches to reduce load.

## Further reading

- [deploy-rs documentation](https://github.com/serokell/deploy-rs)
- [nixos-anywhere documentation](https://github.com/nix-community/nixos-anywhere)
- [colmena documentation](https://colmena.cli.rs/)
- [NixOS Wiki: Deployment](https://nixos.wiki/wiki/Deployment)

Deployment tools transform NixOS from a single-system operating system into a fleet management platform, enabling declarative infrastructure at scale while maintaining the reproducibility and rollback guarantees that make NixOS powerful.
