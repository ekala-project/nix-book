# Secrets Management

Managing secrets in NixOS requires special consideration because of how Nix handles files and the Nix store's global readability. This chapter covers tools and patterns for securely managing credentials, API keys, and other sensitive data.

## Why secrets are special with Nix

### The Nix store is globally readable

The Nix store (`/nix/store`) is world-readable by design. This enables features like binary caching and multi-user Nix, but means anything written to the store can be read by any user on the system:

```nix
# BAD: Never do this!
{
  environment.etc."myapp/config.yaml".text = ''
    api_key: sk-secret-key-12345
    database_password: hunter2
  '';
}
```

When this evaluates, the file content goes into a derivation in `/nix/store`, making your secrets readable by anyone:

```bash
$ ls -l /nix/store/*config.yaml
-r--r--r-- 1 root root 123 Jan 1 12:00 /nix/store/abc123-config.yaml

$ cat /nix/store/abc123-config.yaml
api_key: sk-secret-key-12345
database_password: hunter2
```

Any user can read this file, defeating the purpose of keeping secrets secret.

### Handle secrets through file paths

Instead of embedding secrets in derivations, reference file paths that are managed outside the Nix store. Your NixOS configuration declares *where* secrets should be, and a separate tool handles *what* they contain:

```nix
{
  # Configuration declares the path
  services.myapp.secretFile = "/run/secrets/myapp-key";

  # A secrets management tool provisions the actual file
  # The file is NOT in /nix/store
}
```

At runtime, services read secrets from these paths. The files are created with proper permissions (typically 0400 or 0600) and owned by the appropriate user.

### Runtime services for credential provisioning

NixOS configurations can define systemd services that decrypt or fetch secrets at boot time, before application services start. This keeps secrets encrypted at rest and decrypts them only when needed:

```nix
{
  # Service that decrypts secrets before app starts
  systemd.services.decrypt-secrets = {
    before = [ "myapp.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      # Decrypt secret from encrypted file
      age --decrypt -i /root/.age/key.txt \
        /etc/secrets/encrypted.age > /run/secrets/myapp-key
      chmod 400 /run/secrets/myapp-key
    '';
  };

  # Application service reads from /run/secrets
  systemd.services.myapp = {
    serviceConfig.EnvironmentFile = "/run/secrets/myapp-key";
  };
}
```

This pattern keeps encrypted secrets in version control (safe to commit) while ensuring plaintext secrets only exist in memory and temporary filesystems.

## agenix vs sops-nix

Both agenix and sops-nix solve the same problem—managing encrypted secrets for NixOS—but with different tools and workflows.

### agenix

agenix uses age encryption, a modern, simple alternative to PGP. It integrates tightly with NixOS and focuses on SSH keys for encryption:

**Advantages:**
- Simple, minimal tool (age)
- Uses existing SSH keys for encryption
- Easy to understand file format
- Good NixOS integration
- Automatic secret provisioning via NixOS module

**Workflow:**
1. Encrypt secrets with SSH public keys
2. Store encrypted files in your repository
3. NixOS decrypts them at boot using SSH private keys

**Best for:**
- Teams already using SSH keys
- Simple secret management needs
- Projects wanting minimal dependencies

### sops-nix

sops-nix uses Mozilla SOPS, which supports multiple encryption backends (PGP, age, cloud KMS). It's more flexible but also more complex:

**Advantages:**
- Multiple encryption backend options (age, PGP, AWS KMS, GCP KMS, Azure Key Vault)
- Can encrypt parts of YAML/JSON files (selective encryption)
- Integration with cloud key management systems
- Supports key rotation workflows

**Workflow:**
1. Configure sops with encryption keys (age, PGP, or KMS)
2. Create YAML/JSON files with secrets
3. Encrypt with `sops` command
4. NixOS decrypts at boot

**Best for:**
- Organizations using PGP workflows
- Projects needing cloud KMS integration
- Complex key rotation requirements
- Selective encryption of configuration files

### Choosing between them

Use **agenix** if:
- You want simplicity
- SSH keys are your primary authentication method
- You're just getting started with secrets management

Use **sops-nix** if:
- You need PGP or cloud KMS support
- You want to encrypt parts of config files selectively
- You have existing sops workflows

Both tools are mature and well-maintained. The choice often comes down to which encryption tool (age vs sops) fits your existing workflows better.

## agenix example

### Installation

Add agenix to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, agenix, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        agenix.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### Creating secrets

First, create a `secrets.nix` file defining who can decrypt which secrets:

```nix
# secrets.nix
let
  user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILo...";
  user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBm...";

  system1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEd...";
  system2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINf...";

  allUsers = [ user1 user2 ];
  allSystems = [ system1 system2 ];
in
{
  "database-password.age".publicKeys = allUsers ++ allSystems;
  "api-key.age".publicKeys = allUsers ++ allSystems;
  "smtp-password.age".publicKeys = allUsers ++ [ system1 ];  # Only on system1
}
```

The public keys are SSH public keys from:
- Users (from `~/.ssh/id_ed25519.pub`)
- Systems (from `/etc/ssh/ssh_host_ed25519_key.pub`)

Create and edit secrets:

```bash
# Install agenix CLI
nix profile install github:ryantm/agenix

# Create/edit a secret
agenix -e database-password.age

# This opens your $EDITOR with the decrypted content
# When you save and exit, it re-encrypts for all public keys
```

The encrypted files can be safely committed to git:

```bash
git add secrets.nix database-password.age api-key.age
git commit -m "Add encrypted secrets"
```

### Using secrets in NixOS

Configure secrets in your NixOS configuration:

```nix
{
  # Import the secrets paths
  age.secrets = {
    database-password = {
      file = ./database-password.age;
      owner = "myapp";
      group = "myapp";
      mode = "400";
    };

    api-key = {
      file = ./api-key.age;
      owner = "myapp";
      group = "myapp";
    };
  };

  # Use in services
  systemd.services.myapp = {
    serviceConfig = {
      User = "myapp";
      Group = "myapp";

      # Secret is decrypted to /run/agenix/database-password
      EnvironmentFile = config.age.secrets.database-password.path;
    };

    script = ''
      # Or read directly in script
      API_KEY=$(cat ${config.age.secrets.api-key.path})
      ./myapp --api-key="$API_KEY"
    '';
  };
}
```

At boot, agenix decrypts secrets to `/run/agenix/` with the specified permissions. Services can then read them securely.

### Adding new systems or users

To grant access to a new system:

1. Get the system's SSH host key:
   ```bash
   ssh-keyscan hostname | grep ed25519
   ```

2. Add it to `secrets.nix`:
   ```nix
   system3 = "ssh-ed25519 AAAAC3...";
   allSystems = [ system1 system2 system3 ];
   ```

3. Re-encrypt all secrets:
   ```bash
   agenix -r  # Re-key all secrets
   ```

The secrets are now decryptable by the new system.

## sops-nix example

### Installation

Add sops-nix to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, sops-nix, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };
  };
}
```

### Setting up sops with age

Create an age key for sops:

```bash
# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Get the public key
age-keygen -y ~/.config/sops/age/keys.txt
# Output: age1qw3...
```

For systems, use SSH host keys converted to age format:

```bash
# On the target system
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Create `.sops.yaml` in your repository root:

```yaml
keys:
  - &user1 age1qw3r5t6y7u8i9o0p1a2s3d4f5g6h7j8k9l0
  - &user2 age1z2x3c4v5b6n7m8k9j0h1g2f3d4s5a6p7o8i9
  - &system1 age1s2d3f4g5h6j7k8l9z0x1c2v3b4n5m6q7w8e9
  - &system2 age1a2s3d4f5g6h7j8k9l0p1o2i3u4y5t6r7e8w9

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *user1
          - *user2
          - *system1
          - *system2

  - path_regex: secrets/system1/.*\.yaml$
    key_groups:
      - age:
          - *user1
          - *system1
```

### Creating secrets

Create a YAML file with your secrets:

```yaml
# secrets/prod.yaml
database:
  password: supersecretpassword123
  host: db.example.com

api:
  key: sk-1234567890abcdef
  secret: very-secret-value

smtp:
  password: email-password
```

Encrypt it with sops:

```bash
sops -e secrets/prod.yaml > secrets/prod.enc.yaml
```

The encrypted file looks like:

```yaml
database:
  password: ENC[AES256_GCM,data:jD8fK...,iv:...,tag:...,type:str]
  host: ENC[AES256_GCM,data:mN9sL...,iv:...,tag:...,type:str]
sops:
  kms: []
  gcp_kms: []
  azure_kv: []
  age:
    - recipient: age1qw3r5t6y7u8i9o0p1a2s3d4f5g6h7j8k9l0
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
```

Edit encrypted files:

```bash
sops secrets/prod.enc.yaml
# Opens in $EDITOR, automatically decrypted
# Re-encrypts on save
```

### Using secrets in NixOS

Configure sops-nix in your system:

```nix
{ config, ... }:

{
  # Point to your age key (for the system)
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # Or use SSH host key
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Define secrets
  sops.secrets = {
    "database/password" = {
      sopsFile = ./secrets/prod.enc.yaml;
      owner = "myapp";
      group = "myapp";
    };

    "api/key" = {
      sopsFile = ./secrets/prod.enc.yaml;
      owner = "myapp";
    };
  };

  # Use in services
  systemd.services.myapp = {
    serviceConfig = {
      User = "myapp";
      Group = "myapp";
    };

    script = ''
      # Secrets are available at /run/secrets/<name>
      export DATABASE_PASSWORD=$(cat ${config.sops.secrets."database/password".path})
      export API_KEY=$(cat ${config.sops.secrets."api/key".path})

      ./myapp
    '';
  };
}
```

The secret paths like `"database/password"` correspond to the YAML structure. sops-nix extracts just that value from the encrypted file.

### Selective encryption

sops allows encrypting only specific values in a file:

```bash
# Create unencrypted file
cat > config.yaml <<EOF
public_setting: "this is visible"
database_host: "db.example.com"
database_password: "secret123"
EOF

# Encrypt only the password field
sops -e --encrypted-regex '^.*password$' config.yaml > config.enc.yaml
```

The resulting file has `database_password` encrypted but other fields in plaintext. This is useful for configuration files where only some values are sensitive.

## Other sensitive workflows awkward with Nix

### SSH private keys

SSH private keys need restrictive permissions (0600) and should never touch the Nix store. Deploy them through secrets management or provision them separately:

```nix
{
  # Use agenix or sops-nix for SSH keys
  age.secrets.ssh-key = {
    file = ./secrets/ssh-key.age;
    path = "/home/user/.ssh/id_ed25519";
    owner = "user";
    mode = "600";
  };

  # Or use activation scripts
  system.activationScripts.deploySSHKey = ''
    mkdir -p /home/user/.ssh
    cp /some/secure/location/id_ed25519 /home/user/.ssh/
    chmod 600 /home/user/.ssh/id_ed25519
    chown user:user /home/user/.ssh/id_ed25519
  '';
}
```

### Application secrets in development

Development secrets (local database passwords, test API keys) don't need the same security as production. For convenience, you might:

1. Use environment variables in `.envrc` (not committed)
2. Keep a `secrets.dev.nix` file (in `.gitignore`)
3. Use dummy values in the Nix config and override at runtime

```nix
# configuration.nix - uses placeholder
{
  services.myapp.databaseURL = "postgresql://localhost/myapp";
}
```

```bash
# .envrc (not committed)
export DATABASE_URL="postgresql://realuser:realpass@localhost/myapp"
```

### Certificates and keystores

TLS certificates, Java keystores, and similar files often have specific permission and ownership requirements. Manage them similarly to secrets:

```nix
{
  age.secrets.tls-cert = {
    file = ./secrets/tls-cert.age;
    path = "/var/lib/myapp/cert.pem";
    owner = "myapp";
    mode = "400";
  };

  age.secrets.tls-key = {
    file = ./secrets/tls-key.age;
    path = "/var/lib/myapp/key.pem";
    owner = "myapp";
    mode = "400";
  };
}
```

### Tokens and cookies

Session secrets, JWT signing keys, and CSRF tokens should be randomly generated and rotated. Don't hardcode them in configuration. Instead, generate them at first boot:

```nix
{
  systemd.services.generate-session-secret = {
    before = [ "webapp.service" ];
    wantedBy = [ "multi-user.target" ];

    script = ''
      SECRET_FILE=/var/lib/webapp/session-secret

      if [ ! -f "$SECRET_FILE" ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 32 > "$SECRET_FILE"
        chmod 400 "$SECRET_FILE"
        chown webapp:webapp "$SECRET_FILE"
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
```

This generates a random secret once and persists it across rebuilds.

### Cloud credentials

AWS, GCP, and Azure credentials should not be in Nix configs. Use instance metadata, IAM roles, or managed identities when possible:

```nix
{
  # On AWS EC2, use IAM instance profile (no credentials needed)
  services.myapp.useIAMRole = true;

  # Or store credentials via secrets management
  age.secrets.aws-credentials = {
    file = ./secrets/aws-creds.age;
    path = "/root/.aws/credentials";
    owner = "root";
    mode = "600";
  };
}
```

### Database passwords in services

Database passwords need special care. Different services handle them differently:

**PostgreSQL:**
```nix
{
  services.postgresql = {
    enable = true;
    ensureUsers = [{
      name = "myapp";
      # Password set via psql externally, not in config
    }];
  };

  # Set password via initialization script
  systemd.services.postgresql.postStart = ''
    $PSQL -tAc "ALTER USER myapp PASSWORD '$(cat ${config.age.secrets.db-password.path})'"
  '';
}
```

**Application database connections:**
```nix
{
  systemd.services.myapp = {
    serviceConfig.EnvironmentFile = config.age.secrets.database-url.path;
    # File contains: DATABASE_URL=postgresql://user:password@host/db
  };
}
```

### Multi-environment secrets

Projects with dev/staging/prod environments need separate secrets. Organize by environment:

```
secrets/
├── dev/
│   ├── database.age
│   └── api-keys.age
├── staging/
│   ├── database.age
│   └── api-keys.age
└── prod/
    ├── database.age
    └── api-keys.age
```

Reference the appropriate directory in your configuration:

```nix
{ config, ... }:

let
  environment = "prod";  # Or pass via specialArgs
in
{
  age.secrets.database = {
    file = ./secrets/${environment}/database.age;
  };
}
```

## Best practices

### Never commit plaintext secrets

Always use encryption before committing sensitive data. Add patterns to `.gitignore`:

```gitignore
# Unencrypted secrets
secrets/*.txt
secrets/*.key
*.pem
*.env.local

# Decrypted development files
secrets.dev.nix
```

Commit only encrypted files (`.age`, `.enc.yaml`).

### Use different keys per environment

Production and staging should use separate encryption keys. If staging keys leak, production remains secure. Define separate key groups in your secrets management tool.

### Rotate secrets regularly

Secrets should have lifetimes. Rotate them periodically:

1. Generate new secret
2. Encrypt with new key
3. Deploy to systems
4. Update services
5. Verify functionality
6. Revoke old secret

Both agenix and sops-nix support key rotation workflows.

### Audit secret access

Track who can decrypt secrets. Review `secrets.nix` or `.sops.yaml` regularly:

```bash
# See who can access what
git log secrets.nix

# Review current access
cat secrets.nix
```

Remove keys for users or systems that no longer need access.

### Test secret provisioning

When adding secrets, test on a non-production system first:

```bash
# Build and deploy to test VM
nixos-rebuild switch --flake .#test-vm

# Verify secrets are provisioned
ssh test-vm "ls -l /run/agenix/"
ssh test-vm "cat /run/secrets/api-key"
```

### Document secret requirements

Maintain a README documenting:
- Which secrets exist
- How to add new users/systems
- Rotation procedures
- Emergency access procedures

```markdown
## Secrets

We use agenix for secret management.

### Adding a new system

1. Get the SSH host key: `ssh-keyscan hostname | grep ed25519`
2. Add to `secrets.nix` under `allSystems`
3. Run `agenix -r` to re-encrypt all secrets
4. Commit and deploy

### Rotating secrets

See [ROTATION.md](./ROTATION.md)
```

## Further reading

- [agenix documentation](https://github.com/ryantm/agenix)
- [sops-nix documentation](https://github.com/Mic92/sops-nix)
- [age encryption](https://age-encryption.org/)
- [Mozilla SOPS](https://github.com/mozilla/sops)

Secrets management in NixOS requires understanding the Nix store's limitations and using tools designed to work around them. With agenix or sops-nix, you get declarative secret provisioning while keeping plaintext secrets out of version control and the Nix store.
