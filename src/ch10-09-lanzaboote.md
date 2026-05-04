# lanzaboote

lanzaboote enables Secure Boot on NixOS systems. It provides a seamless way to sign bootloader components and kernel images, allowing NixOS to boot on systems with UEFI Secure Boot enabled.

## Why lanzaboote, and why Secure Boot?

### What is Secure Boot?

Secure Boot is a UEFI firmware feature that ensures only cryptographically signed bootloaders and operating systems can run during system startup. The firmware verifies digital signatures against keys stored in its database before executing boot code.

This prevents:
- Bootkit malware that infects the bootloader
- Rootkits that load before the operating system
- Unauthorized operating systems from booting
- Evil maid attacks that modify boot components

Modern laptops, especially those sold with Windows, ship with Secure Boot enabled by default. The firmware trusts Microsoft's keys, allowing Windows and Microsoft-signed bootloaders to run.

### Why Secure Boot matters

Without Secure Boot, an attacker with physical access can:
1. Boot from a USB drive to access your encrypted drive
2. Modify bootloader or kernel files to inject malware
3. Install a rootkit that persists across reboots
4. Bypass full-disk encryption by compromising the boot process

Secure Boot mitigates these attacks by ensuring boot components haven't been tampered with. Combined with disk encryption, it provides a more complete security posture.

### The NixOS challenge

Traditional Linux distributions handle Secure Boot by using a Microsoft-signed shim bootloader that then loads their distribution-specific bootloader. NixOS's unique approach to system management makes this more complex:

- Each system generation has its own kernel and initrd
- Bootloader configuration changes with every rebuild
- Files need signing at build time, not installation time
- Multiple generations must coexist and all be bootable

Standard Secure Boot tools don't handle NixOS's multi-generation model well. You'd need to manually sign every kernel and initrd for every generation—tedious and error-prone.

### Why lanzaboote?

lanzaboote solves this by integrating Secure Boot signing into the NixOS build process. It:

- Automatically signs bootloader components during system activation
- Handles multiple system generations transparently
- Integrates with NixOS's declarative configuration model
- Uses your own keys (not Microsoft's)
- Maintains NixOS's rollback capability

With lanzaboote, Secure Boot becomes declarative. You configure it once in your NixOS configuration, and it handles signing automatically for all future system generations.

## Setting up lanzaboote

### Prerequisites

Before enabling lanzaboote, ensure:

1. Your system uses UEFI (not legacy BIOS)
2. Your system supports Secure Boot
3. You have physical access to enter UEFI setup
4. You're using systemd-boot (not GRUB)

Check if your system has Secure Boot:

```bash
bootctl status | grep "Secure Boot"
# Should show: Secure Boot: disabled
```

If it shows "disabled," your hardware supports it but it's currently off.

### Installation

Add lanzaboote to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, lanzaboote, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        lanzaboote.nixosModules.lanzaboote
        ./configuration.nix
      ];
    };
  };
}
```

### Generating Secure Boot keys

Lanzaboote uses your own cryptographic keys to sign boot components. Generate these keys outside the Nix store for security:

```bash
# Create directory for keys (outside /nix/store!)
sudo mkdir -p /var/lib/secureboot
cd /var/lib/secureboot

# Generate keys using sbctl
sudo nix run nixpkgs#sbctl create-keys
```

This creates several keys:
- `PK` (Platform Key) - The root of trust
- `KEK` (Key Exchange Key) - Authorizes signature databases
- `db` (Signature Database) - Contains authorized signing keys

These keys live in `/var/lib/secureboot` and should never be committed to version control or placed in the Nix store.

### Configuring NixOS

Enable lanzaboote in your configuration:

```nix
{ config, pkgs, lib, ... }:

{
  # Ensure systemd-boot is enabled
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Enable lanzaboote
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/secureboot";
  };

  # Required: TPM support is often needed
  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true;
  security.tpm2.tctiEnvironment.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl  # Useful for managing Secure Boot
  ];
}
```

Note that `systemd-boot.enable` is set to `false`—lanzaboote replaces systemd-boot with a signed version.

### Building and installing

Rebuild your system:

```bash
sudo nixos-rebuild switch --flake .#hostname
```

Lanzaboote signs the bootloader, kernel, and initrd during activation. Verify the signatures:

```bash
sudo sbctl verify
```

You should see output showing signed components:
```
Verifying file database and EFI images in /boot...
✓ /boot/EFI/BOOT/BOOTX64.EFI is signed
✓ /boot/EFI/Linux/nixos-generation-1.efi is signed
✓ /boot/EFI/Linux/nixos-generation-2.efi is signed
✓ /boot/EFI/systemd/systemd-bootx64.efi is signed
```

### Enrolling keys in firmware

The final step is enrolling your keys into the UEFI firmware. This tells the firmware to trust your signatures:

```bash
sudo sbctl enroll-keys --microsoft
```

The `--microsoft` flag also enrolls Microsoft's keys, allowing you to boot Windows or other Microsoft-signed bootloaders alongside NixOS. Omit it if you want NixOS-only booting.

**Warning:** After this step, only signed bootloaders will work. Ensure your NixOS install is correctly signed before proceeding.

Reboot and enter UEFI setup (usually F2, F12, Del, or Esc during boot). Enable Secure Boot in the firmware settings.

### First Secure Boot

After enabling Secure Boot, reboot. Your system should boot normally into NixOS. Verify Secure Boot is active:

```bash
bootctl status | grep "Secure Boot"
# Should show: Secure Boot: enabled
```

If it boots successfully, Secure Boot is working! All future system generations will be automatically signed by lanzaboote.

## Common issues

### System won't boot after enabling Secure Boot

When the system fails to boot with Secure Boot enabled, the firmware isn't accepting your signatures. This usually means keys weren't properly enrolled or the bootloader isn't signed. Disable Secure Boot in UEFI settings to regain access, then verify:

```bash
# Check if keys are enrolled
sudo sbctl status

# Verify components are signed
sudo sbctl verify

# Re-enroll keys if needed
sudo sbctl enroll-keys --microsoft
```

After re-enrolling, rebuild the system to ensure everything is signed:

```bash
sudo nixos-rebuild switch --flake .#hostname
sudo sbctl verify
```

Only enable Secure Boot again after confirming all components show as signed.

### Missing TPM support

Some lanzaboote features require TPM (Trusted Platform Module) support. If your system has a TPM but lanzaboote can't access it, ensure the kernel modules are loaded:

```nix
{
  boot.initrd.availableKernelModules = [ "tpm_tis" "tpm_crb" ];

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };
}
```

Check if TPM is detected:

```bash
ls /dev/tpm*
# Should show /dev/tpm0 or /dev/tpmrm0
```

If no TPM devices appear, check UEFI settings—TPM might be disabled in firmware.

### Old generations won't boot

After enabling Secure Boot, generations created before lanzaboote was configured won't boot because they're unsigned. When you try to boot an old generation, the firmware rejects the unsigned kernel. To fix this, lanzaboote automatically signs all existing generations during activation:

```bash
sudo nixos-rebuild switch --flake .#hostname
```

This signs all bootable generations in `/boot`. Verify with:

```bash
sudo sbctl verify
```

Each generation should show as signed. If some are missing, they might have been garbage collected or weren't properly signed during activation.

### Keys lost or corrupted

If your Secure Boot keys in `/var/lib/secureboot` are lost or corrupted, you'll need to regenerate them and re-enroll. This requires disabling Secure Boot temporarily:

1. Disable Secure Boot in UEFI settings
2. Boot into NixOS
3. Generate new keys:
   ```bash
   sudo rm -rf /var/lib/secureboot/*
   sudo sbctl create-keys
   ```
4. Rebuild system:
   ```bash
   sudo nixos-rebuild switch --flake .#hostname
   ```
5. Verify signatures:
   ```bash
   sudo sbctl verify
   ```
6. Enroll new keys:
   ```bash
   sudo sbctl enroll-keys --microsoft
   ```
7. Re-enable Secure Boot in UEFI

Backup your keys after generating them:

```bash
sudo tar czf ~/secureboot-keys-backup.tar.gz /var/lib/secureboot
# Store this backup somewhere safe and offline
```

### systemd-boot conflicts

When lanzaboote is enabled, systemd-boot must be disabled to avoid conflicts. If you see errors about conflicting bootloader configuration, ensure your config has:

```nix
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote.enable = true;
}
```

The `lib.mkForce` ensures lanzaboote's setting takes precedence over any other modules that might enable systemd-boot.

### Different architecture (aarch64)

Lanzaboote primarily targets x86_64 systems. ARM64 (aarch64) Secure Boot works differently and may not be fully supported. Check the [lanzaboote documentation](https://github.com/nix-community/lanzaboote) for current architecture support.

For ARM systems, Secure Boot often requires vendor-specific keys and processes. Consult your hardware manufacturer's documentation.

### Dual-booting with Windows

When dual-booting with Windows, you need Microsoft's keys enrolled to boot Windows. Always use the `--microsoft` flag when enrolling keys:

```bash
sudo sbctl enroll-keys --microsoft
```

This enrolls both your keys (for NixOS) and Microsoft's keys (for Windows). Windows should continue to boot normally alongside NixOS.

If Windows stops booting after enrolling keys without `--microsoft`, re-enroll with the flag:

```bash
sudo sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine
```

The scary-looking flag confirms you understand the risks of modifying firmware key databases.

### Secure Boot validation failures

Sometimes the firmware rejects signatures even though `sbctl verify` shows everything as signed. This can happen if:

- Firmware has outdated or buggy Secure Boot implementation
- Keys were enrolled incorrectly
- Firmware key database is corrupted

Try clearing the key database and re-enrolling:

1. Enter UEFI setup
2. Find Secure Boot settings
3. Look for "Clear Secure Boot keys" or "Restore factory keys"
4. Clear/restore keys
5. Boot into NixOS (Secure Boot disabled automatically after clearing)
6. Re-enroll your keys:
   ```bash
   sudo sbctl enroll-keys --microsoft
   ```
7. Re-enable Secure Boot

## Maintaining Secure Boot

### Regular system updates

Lanzaboote automatically signs new generations during rebuild:

```bash
sudo nixos-rebuild switch --flake .#hostname
```

Each rebuild creates a new generation and signs its kernel and initrd. No manual intervention needed—Secure Boot continues working across updates.

### Verifying signature status

Periodically verify all bootable components are signed:

```bash
sudo sbctl verify
```

This checks:
- Bootloader binaries
- Kernel images
- Initrd images
- All bootable generations

Any unsigned components indicate a problem with lanzaboote configuration.

### Key rotation

For maximum security, rotate Secure Boot keys periodically (annually or biannually):

1. Disable Secure Boot in UEFI
2. Generate new keys:
   ```bash
   sudo sbctl create-keys
   ```
3. Rebuild system with new keys:
   ```bash
   sudo nixos-rebuild switch --flake .#hostname
   ```
4. Verify signatures:
   ```bash
   sudo sbctl verify
   ```
5. Enroll new keys:
   ```bash
   sudo sbctl enroll-keys --microsoft
   ```
6. Re-enable Secure Boot

Old keys become invalid after enrollment, preventing previously-signed bootloaders from running.

### Monitoring boot integrity

Use systemd's boot loader log to track boot attempts:

```bash
bootctl list
```

This shows all available boot entries and which ones booted successfully. Unexpected entries might indicate tampering.

Check firmware event log for Secure Boot violations:

```bash
sudo dmesg | grep -i "secure boot"
```

Look for messages about signature verification failures or unauthorized boot attempts.

## Integration with other security features

### Full disk encryption

Lanzaboote works seamlessly with LUKS full-disk encryption. The boot process becomes:

1. Firmware verifies lanzaboote signature
2. Lanzaboote loads signed kernel and initrd
3. Initrd prompts for LUKS passphrase
4. System decrypts root partition and continues boot

Configure encryption normally:

```nix
{
  boot.initrd.luks.devices.root = {
    device = "/dev/disk/by-uuid/...";
    preLVM = true;
  };

  boot.lanzaboote.enable = true;
}
```

This provides defense in depth: Secure Boot protects boot components, LUKS protects data at rest.

### TPM-based encryption

For stronger security, use TPM to seal encryption keys, releasing them only when Secure Boot verification passes:

```nix
{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices.root = {
    device = "/dev/disk/by-uuid/...";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };

  security.tpm2.enable = true;
  boot.lanzaboote.enable = true;
}
```

The TPM unseals the encryption key only if:
- Secure Boot verification passed
- Boot components haven't been modified
- System configuration matches expected measurements

This creates automatic unlocking with strong security guarantees.

### Measured boot

Lanzaboote supports measured boot, where the TPM records measurements of boot components. This creates a chain of trust:

```nix
{
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/secureboot";
  };

  security.tpm2.enable = true;
}
```

Boot measurements are stored in TPM PCRs (Platform Configuration Registers). Verify them:

```bash
sudo tpm2_pcrread
```

Changes to boot components alter PCR values, allowing detection of unauthorized modifications.

## Best practices

### Backup your keys

Secure Boot keys are critical. Losing them means you can't boot your system with Secure Boot enabled. Create encrypted backups:

```bash
sudo tar czf /tmp/secureboot-keys.tar.gz /var/lib/secureboot
gpg -c /tmp/secureboot-keys.tar.gz
# Store secureboot-keys.tar.gz.gpg somewhere safe
sudo rm /tmp/secureboot-keys.tar.gz*
```

Store the encrypted backup on external media and in a secure location (not on the encrypted drive itself).

### Test before full deployment

Before enabling Secure Boot on production systems, test on a non-critical machine. Verify:
- System boots successfully with Secure Boot enabled
- All generations are signed and bootable
- Rollback functionality works
- TPM integration (if used) functions correctly

### Document your setup

Maintain documentation of:
- When keys were generated
- Where backups are stored
- Emergency access procedures (if keys are lost)
- Key rotation schedule

```markdown
## Secure Boot Configuration

- Keys generated: 2024-01-15
- Keys backed up to: encrypted USB drive in safe
- Key rotation schedule: annually, every January
- Emergency procedure: See SECURE-BOOT-RECOVERY.md
```

### Use hardware tokens for key storage

For maximum security, store signing keys on hardware tokens (YubiKey, Nitrokey). This prevents key extraction even if the system is compromised. Lanzaboote doesn't directly support this, but you can sign components manually using the hardware token and configure lanzaboote to use pre-signed images.

### Combine with verified boot

For critical systems, combine Secure Boot with verified boot/integrity checking:

```nix
{
  boot.lanzaboote.enable = true;

  # dm-verity for read-only root
  boot.initrd.systemd.enable = true;

  # IMA/EVM for runtime integrity
  security.ima = {
    enable = true;
    policy = "tcb";
  };
}
```

This provides protection throughout the system lifecycle, not just at boot.

## Further reading

- [lanzaboote documentation](https://github.com/nix-community/lanzaboote)
- [sbctl documentation](https://github.com/Foxboron/sbctl)
- [UEFI Secure Boot specification](https://uefi.org/specifications)
- [NixOS Wiki: Secure Boot](https://nixos.wiki/wiki/Secure_Boot)

Lanzaboote brings Secure Boot to NixOS in a way that preserves the distribution's unique multi-generation model. With proper setup and key management, it significantly enhances system security against boot-time attacks.
