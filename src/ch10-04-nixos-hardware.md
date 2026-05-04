# nixos-hardware

nixos-hardware is a community-maintained collection of NixOS modules that provide hardware-specific configuration for various devices. It handles quirks, optimizations, and necessary tweaks for specific laptop and desktop models.

## Value proposition

### Hardware-specific configuration without the hassle

Different hardware requires different configuration to work optimally on Linux. Common issues include:

- Graphics drivers (Intel, AMD, NVIDIA)
- Power management and battery life
- WiFi and Bluetooth firmware
- Touchpad and input devices
- Display scaling and HiDPI
- Thermal management
- Special function keys

nixos-hardware provides pre-tested, community-maintained modules that handle these configurations:

```nix
{
  imports = [
    <nixos-hardware/lenovo/thinkpad/t480>
  ];
}
```

This single import configures everything specific to the ThinkPad T480: graphics, power management, touchpad, etc.

### Community knowledge captured as code

Instead of hunting through wikis, forums, and bug trackers, nixos-hardware packages hardware-specific knowledge as reusable NixOS modules:

- **Tested configurations**: Modules are tested by actual users of that hardware
- **Best practices**: Captures the collective wisdom of the NixOS community
- **Version controlled**: Changes and improvements are tracked over time
- **Easy to contribute**: Found a fix? Submit a PR to help others

### Faster hardware enablement

New hardware often requires specific kernel patches, firmware, or driver versions. nixos-hardware modules can:

- Enable specific kernel versions or patches
- Include necessary firmware packages
- Set kernel parameters for hardware support
- Configure bootloader options
- Enable required system services

This dramatically reduces the time from "bought new laptop" to "fully working NixOS installation."

## How to use nixos-hardware

### With flakes (recommended)

Add nixos-hardware as an input to your flake:

```nix
{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixos-hardware.nixosModules.lenovo-thinkpad-t480
      ];
    };
  };
}
```

Available module names match the directory structure in the repository:
- `nixos-hardware.nixosModules.lenovo-thinkpad-t480`
- `nixos-hardware.nixosModules.dell-xps-13-9380`
- `nixos-hardware.nixosModules.raspberry-pi-4`
- etc.

### Without flakes (legacy)

Add nixos-hardware as a channel or fetchTarball:

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  imports = [
    # Using channel
    <nixos-hardware/lenovo/thinkpad/t480>

    # Or using fetchTarball for pinning
    "${builtins.fetchTarball "https://github.com/NixOS/nixos-hardware/archive/master.tar.gz"}/lenovo/thinkpad/t480"
  ];
}
```

Add the channel:

```bash
sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
sudo nix-channel --update
```

## Finding configuration for your hardware

### Browse the repository

The easiest way is to browse the [nixos-hardware GitHub repository](https://github.com/NixOS/nixos-hardware):

```
https://github.com/NixOS/nixos-hardware/tree/master
```

The directory structure is organized by manufacturer and model:

```
nixos-hardware/
├── apple/
│   ├── macbook-pro/
│   │   ├── 11-5/
│   │   └── 12-1/
│   └── t2/
├── dell/
│   ├── xps/
│   │   ├── 13-9380/
│   │   ├── 15-7590/
│   │   └── 15-9560/
│   └── latitude/
├── framework/
│   ├── 13-inch/
│   │   ├── 7040-amd/
│   │   └── common/
│   └── 16-inch/
├── lenovo/
│   ├── thinkpad/
│   │   ├── t14/
│   │   ├── t480/
│   │   ├── x1/
│   │   │   ├── 7th-gen/
│   │   │   └── extreme/
│   │   └── ...
│   └── ideapad/
├── raspberry-pi/
│   ├── 4/
│   └── 5/
└── ...
```

### Check for your specific model

Look for your manufacturer, then your model. For example:

- **Lenovo ThinkPad T480**: `lenovo/thinkpad/t480`
- **Dell XPS 13 9380**: `dell/xps/13-9380`
- **Framework Laptop 13 (AMD)**: `framework/13-inch/7040-amd`
- **Raspberry Pi 4**: `raspberry-pi/4`

### Check common profiles

If your exact model isn't listed, check for:

1. **Generic manufacturer profiles**: Some manufacturers have common quirks
2. **Related models**: A similar model might work well enough
3. **Component-specific modules**: GPU, WiFi chipset, etc.

For example, the repository includes:

- `common/cpu/intel` - Intel CPU optimizations
- `common/cpu/amd` - AMD CPU optimizations
- `common/gpu/nvidia` - NVIDIA GPU configuration
- `common/gpu/amd` - AMD GPU configuration
- `common/pc/laptop` - Generic laptop power management

### Use multiple modules

You can combine multiple modules:

```nix
{
  imports = [
    nixos-hardware.nixosModules.common-cpu-intel
    nixos-hardware.nixosModules.common-gpu-nvidia
    nixos-hardware.nixosModules.common-pc-laptop
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];
}
```

More specific modules override generic ones, so this is safe.

## Inspecting what a module does

To understand what a hardware module configures, read its source:

```bash
# Clone the repository
git clone https://github.com/NixOS/nixos-hardware.git
cd nixos-hardware

# View a specific module
cat lenovo/thinkpad/t480/default.nix
```

Example module structure:

```nix
{ lib, pkgs, ... }:

{
  imports = [
    ../../../common/cpu/intel
    ../../../common/pc/laptop
    ../../../common/pc/laptop/ssd
  ];

  # Enable TLP for better battery life
  services.tlp.enable = lib.mkDefault true;

  # Thunderbolt support
  services.hardware.bolt.enable = lib.mkDefault true;

  # Firmware
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # Trackpoint configuration
  boot.kernelParams = [
    "psmouse.synaptics_intertouch=1"
  ];
}
```

Notice the use of `lib.mkDefault` - this means you can still override these settings in your own configuration if needed.

## Contributing configuration for new hardware

Found yourself configuring a new piece of hardware? Share it with the community!

### When to contribute

Consider contributing when:

- Your hardware required specific configuration to work properly
- You found settings that improve performance or battery life
- You needed specific kernel parameters or modules
- The configuration would benefit other users of the same hardware

### What to include

A good hardware module typically includes:

1. **CPU/GPU optimizations**: Appropriate power management, drivers
2. **Firmware**: Required firmware packages
3. **Kernel parameters**: Boot parameters needed for hardware
4. **Services**: TLP, fwupd, or hardware-specific daemons
5. **Input devices**: Touchpad, trackpoint, special keys configuration
6. **Known issues**: Comments documenting workarounds

### Contribution steps

1. **Test your configuration**: Make sure it works on your hardware
2. **Fork the repository**: `https://github.com/NixOS/nixos-hardware`
3. **Create a directory structure**: `manufacturer/model/`
4. **Write the module**: Create `default.nix` with your configuration
5. **Add a README**: Document what works, what doesn't, and any caveats
6. **Submit a pull request**: Include testing notes and hardware details

### Example contribution structure

```
nixos-hardware/
└── manufacturer/
    └── model/
        ├── default.nix       # Main configuration
        └── README.md         # Documentation
```

`default.nix`:

```nix
{ lib, pkgs, ... }:

{
  imports = [
    # Import common profiles
    ../../common/cpu/amd
    ../../common/gpu/amd
    ../../common/pc/laptop
    ../../common/pc/laptop/ssd
  ];

  # Firmware
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # Power management
  services.tlp = {
    enable = lib.mkDefault true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
    };
  };

  # Kernel parameters for this specific hardware
  boot.kernelParams = [
    "amd_iommu=on"
  ];

  # Audio fixes
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=auto
  '';
}
```

`README.md`:

```markdown
# Manufacturer Model

## Tested Hardware

- CPU: AMD Ryzen 7 5800U
- GPU: AMD Radeon Graphics (integrated)
- RAM: 16GB
- Disk: 512GB NVMe SSD

## What works

- WiFi and Bluetooth
- Suspend and hibernate
- Function keys
- Audio (speakers and headphone jack)
- Webcam and microphone
- USB-C charging and display

## What doesn't work

- Fingerprint reader (no Linux driver available)

## Notes

- Battery life is excellent with TLP enabled
- Suspend occasionally takes 5-10 seconds to complete
```

## Common issues

### Module not found

**Problem**: Import fails with "path not found"

```
error: file 'nixos-hardware/...' was not found in the Nix search path
```

**Solution**:

With flakes, ensure nixos-hardware is in your inputs:

```nix
inputs = {
  nixos-hardware.url = "github:NixOS/nixos-hardware";
};
```

Without flakes, add the channel:

```bash
sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
sudo nix-channel --update
```

### Conflicts with existing configuration

**Problem**: Hardware module conflicts with your settings

**Solution**: Hardware modules use `lib.mkDefault`, so you can override:

```nix
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

  # This overrides the module's setting
  services.tlp.enable = false;

  # Or use mkForce for stronger override
  services.tlp.enable = lib.mkForce false;
}
```

### Module is outdated

If the hardware module doesn't work with recent NixOS/kernel

1. Check if there's a newer version in the repository
2. Update your nixos-hardware input: `nix flake update nixos-hardware`
3. File an issue or PR with fixes
4. Temporarily override problematic settings

### Too generic or too specific

If the module is either too generic (doesn't fix your issues) or too specific (configures things you don't want)

Mix and match modules:

```nix
{
  imports = [
    # Use generic modules
    nixos-hardware.nixosModules.common-cpu-intel
    nixos-hardware.nixosModules.common-gpu-nvidia

    # Add your own hardware-specific tweaks
    ./my-hardware-tweaks.nix
  ];
}
```

Or fork the module and adjust it for your needs.

### NVIDIA driver issues

NVIDIA modules are quite hard to configure generically, you may need to configure for your use case

```nix
{
  imports = [
    nixos-hardware.nixosModules.common-gpu-nvidia
  ];

  # You may need additional configuration
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;  # Use proprietary driver
    nvidiaSettings = true;
  };
}
```

Check the [NixOS wiki for NVIDIA](https://nixos.wiki/wiki/Nvidia) for detailed configuration.

### Module enables unwanted services

Sometimes the hardware module enables services which are generally preferred, but may not be in your case.

```nix
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

  # Disable TLP if you prefer another power manager
  services.tlp.enable = lib.mkForce false;
  services.power-profiles-daemon.enable = true;
}
```

## Useful nixos-hardware modules

### Popular laptops

- `lenovo-thinkpad-t14` - ThinkPad T14 (Gen 1-3)
- `lenovo-thinkpad-x1-7th-gen` - ThinkPad X1 Carbon Gen 7
- `dell-xps-13-9380` - Dell XPS 13
- `dell-xps-15-7590` - Dell XPS 15
- `framework-13-inch-7040-amd` - Framework Laptop 13 (AMD)
- `apple-t2` - Apple devices with T2 chip

### Single-board computers

- `raspberry-pi-4` - Raspberry Pi 4
- `raspberry-pi-5` - Raspberry Pi 5

### Common profiles

- `common-cpu-intel` - Intel CPU optimizations
- `common-cpu-amd` - AMD CPU optimizations
- `common-gpu-nvidia` - NVIDIA GPU configuration
- `common-gpu-amd` - AMD GPU configuration
- `common-pc-laptop` - Generic laptop power management
- `common-pc-laptop-ssd` - SSD-specific optimizations
- `common-pc-laptop-hdd` - HDD-specific optimizations

Browse the full list at: https://github.com/NixOS/nixos-hardware

## Beyond nixos-hardware

If nixos-hardware doesn't have a module for your device:

1. **Check common profiles**: Start with CPU/GPU profiles
2. **Search NixOS Discourse/Reddit**: Others may have shared configs
3. **Check the NixOS wiki**: Hardware-specific pages exist for many devices
4. **Contribute back**: Once you have it working, submit a PR!

Remember: nixos-hardware is community-maintained. The best way to improve it is to contribute your own configurations.
