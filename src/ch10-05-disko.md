# disko

disko is a tool for declarative disk partitioning in NixOS. It allows you to define your entire disk layout—partitions, filesystems, encryption, LVM, RAID—in a Nix configuration file.

## Value proposition

### Declarative partitioning

Traditional Linux installation requires manual partitioning with tools like `fdisk`, `parted`, or `gparted`. This is:

- **Error-prone**: Easy to make mistakes during initial setup
- **Undocumented**: The disk layout exists only on the disk itself
- **Not reproducible**: Reinstalling requires remembering or rediscovering the layout
- **Not version-controlled**: Changes to disk layout aren't tracked

disko makes disk layout declarative:

```nix
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "512M";
            type = "EF00";
            content.type = "filesystem";
            content.format = "vfat";
            content.mountpoint = "/boot";
          };
          root = {
            size = "100%";
            content.type = "filesystem";
            content.format = "ext4";
            content.mountpoint = "/";
          };
        };
      };
    };
  };
}
```

This configuration:
- Lives in your NixOS configuration
- Is version-controlled with git
- Can be reused across multiple machines
- Documents your disk layout as code
- Can be applied automatically during installation

### Automated installation

disko can format and partition disks automatically:

```bash
# Apply the disk configuration
sudo nix run github:nix-community/disko -- --mode disko /path/to/disko-config.nix
```

This makes NixOS installation faster and more reliable, especially for:
- Automated deployments
- Multiple identical machines
- Disaster recovery
- Testing installation in VMs

### Complex layouts made simple

disko handles complex setups that would be tedious manually:

- Full disk encryption (LUKS)
- LVM with multiple volumes
- RAID configurations
- Btrfs subvolumes
- ZFS pools and datasets
- Hybrid setups (e.g., encrypted LVM with multiple filesystems)

These are all expressed in the same declarative format.

## Getting started

### Installation

disko is typically used during NixOS installation, but can be added to an existing system:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        disko.nixosModules.disko
        ./disko-config.nix
        ./configuration.nix
      ];
    };
  };
}
```

### Basic workflow

1. **Define your disk layout** in a `disko-config.nix` file
2. **Apply the configuration** to partition and format disks
3. **Install NixOS** as usual, or include disko config in your system

During installation:

```bash
# 1. Apply disk configuration
sudo nix run github:nix-community/disko -- --mode disko ./disko-config.nix

# 2. Install NixOS
sudo nixos-install --flake .#hostname
```

## Common partition layouts

### Simple single-disk layout

The most basic setup: boot partition and root partition.

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # BIOS boot partition
            };
            ESP = {
              size = "512M";
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
  };
}
```

This creates:
- 1MB BIOS boot partition (for GRUB on legacy systems)
- 512MB ESP (EFI System Partition) mounted at `/boot`
- Remainder as ext4 root filesystem

### Layout with swap

Adding a swap partition:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
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
  };
}
```

### Separate home partition

Keep `/home` on a separate partition:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "50G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            home = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/home";
              };
            };
          };
        };
      };
    };
  };
}
```

### Btrfs with subvolumes

Btrfs subvolumes for better snapshot management:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
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
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                  };
                  "@home" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/home";
                  };
                  "@nix" = {
                    mountOptions = [ "compress=zstd" "noatime" ];
                    mountpoint = "/nix";
                  };
                  "@snapshots" = {
                    mountpoint = "/snapshots";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

This creates a single Btrfs partition with multiple subvolumes:
- `@` for root
- `@home` for user data with compression
- `@nix` for the Nix store with compression and noatime
- `@snapshots` for storing snapshots

### LVM setup

Using LVM for flexibility:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            lvm = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "main_vg";
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      main_vg = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "8G";
            content = {
              type = "swap";
            };
          };
          root = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
          home = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/home";
            };
          };
        };
      };
    };
  };
}
```

This creates:
- Physical volume on the main partition
- Volume group named `main_vg`
- Logical volumes for swap, root, and home

## Encrypted drive example

### Full disk encryption with LUKS

Encrypt the entire root partition:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  allowDiscards = true;
                };
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
  };
}
```

During installation, you'll be prompted for a passphrase. On boot, you'll need to enter it to unlock the disk.

### Encrypted LVM

Combine encryption with LVM for maximum flexibility:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  allowDiscards = true;
                  bypassWorkqueues = true;
                };
                content = {
                  type = "lvm_pv";
                  vg = "main_vg";
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      main_vg = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "8G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };
          root = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
          home = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/home";
            };
          };
        };
      };
    };
  };
}
```

This setup:
- Encrypts a single partition with LUKS
- Creates LVM physical volume inside the encrypted partition
- Creates multiple logical volumes (swap, root, home) inside

### Encrypted Btrfs

Encryption with Btrfs subvolumes:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                    };
                    "@home" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/home";
                    };
                    "@nix" = {
                      mountOptions = [ "compress=zstd" "noatime" ];
                      mountpoint = "/nix";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

## Common issues

### Wrong disk device

disko tries to partition the wrong disk or disk doesn't exist

```
error: device /dev/sda not found
```

Check your disk device name first, and ensure it's the correct device name:

```bash
lsblk
```

Update your configuration to match the actual device:

```nix
{
  disko.devices.disk.main.device = "/dev/nvme0n1";  # Not /dev/sda
}
```

Modern systems often use:
- NVMe drives: `/dev/nvme0n1`, `/dev/nvme1n1`, etc.
- SATA/SAS drives: `/dev/sda`, `/dev/sdb`, etc.
- Virtual machines: `/dev/vda`, `/dev/vdb`, etc.

### Disk already has data

disko refuses to partition a disk with existing data, as disko is cautious by default. To force partitioning:

```bash
# WARNING: This destroys all data on the disk!
sudo nix run github:nix-community/disko -- --mode destroy ./disko-config.nix
sudo nix run github:nix-community/disko -- --mode disko ./disko-config.nix
```

Or wipe the disk manually first:

```bash
sudo wipefs -a /dev/sda
```

### Partition size too large

When the total partition sizes exceed disk size, you will see the following error:

```
error: not enough space on disk
```

To rememdy this, check your sizes add up correctly:

```nix
{
  # Bad: 512M + 100G + 100% will fail on a 100GB disk
  partitions = {
    ESP.size = "512M";
    root.size = "100G";
    home.size = "100%";  # Won't fit!
  };

  # Good: Last partition uses remaining space
  partitions = {
    ESP.size = "512M";
    root.size = "50G";
    home.size = "100%";  # Gets whatever is left
  };
}
```

### LUKS passphrase during installation

You will need to enter passphrase multiple times during installation, as the workflow is:

1. Create the encrypted partition
2. Mount it for installation
3. Configure initrd to prompt for it on boot

After installation, you'll only need to enter it once per boot.

### Can't mount after applying disko

In certain cases, you may get an error that partitions exist but won't mount.

In this case, be sure to check that disko ran in the correct mode:

```bash
# Just partition and format (doesn't mount)
sudo nix run github:nix-community/disko -- --mode disko ./disko-config.nix

# Partition, format, and mount
sudo nix run github:nix-community/disko -- --mode disko --mount /mnt ./disko-config.nix
```

For installation, you want the second form to mount at `/mnt`.

### Btrfs subvolume mount issues

Btrfs subvolumes don't mount correctly as they are sensitive to mount options, ensure your properly communicate them.


```nix
{
  subvolumes = {
    "@" = {
      mountpoint = "/";
      mountOptions = [ "subvol=@" ];  # Explicitly specify subvol
    };
    "@home" = {
      mountpoint = "/home";
      mountOptions = [ "subvol=@home" "compress=zstd" ];
    };
  };
}
```

### LVM volume group name conflicts

LVM volume group already exist when using the same name, ensure you use unique volume group names.


```nix
{
  lvm_vg = {
    main_vg = {  # Make sure this name is unique
      type = "lvm_vg";
      # ...
    };
  };
}
```

Or remove the old volume group:

```bash
sudo vgremove main_vg
```

### TRIM/discard on encrypted SSD

SSD performance degrades over time with encryption, you may want to enable discards in LUKS settings:

```nix
{
  content = {
    type = "luks";
    settings = {
      allowDiscards = true;  # Enable TRIM for SSDs
      bypassWorkqueues = true;  # Performance improvement
    };
  };
}
```

Note: Enabling discards on encrypted volumes has minor security implications (reveals which blocks are unused), but is generally acceptable for personal use.

## Advanced disko patterns

### Conditional disk layouts

Use different layouts for different machines:

```nix
{ lib, ... }:
let
  hostname = "laptop";  # or get from config

  diskConfig = if hostname == "laptop" then {
    # Laptop config with encryption
    device = "/dev/nvme0n1";
    encrypted = true;
  } else {
    # Server config without encryption
    device = "/dev/sda";
    encrypted = false;
  };
in
{
  disko.devices = # ... use diskConfig
}
```

**Note:** it may be advisable to just have a dedicated disko config per machine instead of coupling them to branching logic.

### Multi-disk setups

Configure multiple disks:

```nix
{
  disko.devices = {
    disk = {
      ssd = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
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
      hdd = {
        type = "disk";
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/data";
              };
            };
          };
        };
      };
    };
  };
}
```

### ZFS pools

For ZFS enthusiasts:

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
          };
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.compression = "zstd";
          };
        };
      };
    };
  };
}
```

## Further reading

- [disko GitHub repository](https://github.com/nix-community/disko)
- [disko examples directory](https://github.com/nix-community/disko/tree/master/example)
- [NixOS installation guide](https://nixos.org/manual/nixos/stable/index.html#sec-installation)

disko makes NixOS installation more reproducible and maintainable. Once you have a working configuration, reinstalling or deploying to new machines becomes a matter of minutes rather than hours.
