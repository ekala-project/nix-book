# devenv

devenv is a fast, declarative tool for creating development environments with Nix. It provides a higher-level interface than raw `mkShell` and includes built-in support for common development workflows, services, and language ecosystems.

## Value proposition

### Developer-focused abstractions

While `mkShell` is powerful, it requires understanding Nix language details and manually configuring common development tools. devenv provides pre-configured modules for languages, databases, and services:

```nix
# Traditional mkShell approach
{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    nodejs
    postgresql
    redis
  ];

  shellHook = ''
    export DATABASE_URL="postgresql://localhost/mydb"
    # Start postgres manually...
    # Start redis manually...
  '';
}

# devenv approach
{
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs;
  };

  services.postgres = {
    enable = true;
    initialDatabases = [{ name = "mydb"; }];
  };

  services.redis.enable = true;
}
```

devenv handles service lifecycle, environment variables, and common configuration patterns automatically.

### Built-in service management

Development often requires running background services like databases, message queues, or cache servers. devenv includes process management through `process-compose`, allowing you to start all services with a single command:

```bash
devenv up
```

This starts all configured services in the foreground with proper logging and health checks, similar to docker-compose but with Nix's reproducibility guarantees.

### Fast iteration

devenv is optimized for quick feedback loops. It caches evaluation aggressively and provides fast commands for common operations:

- `devenv shell` - Enter the development environment
- `devenv test` - Run tests defined in your configuration
- `devenv update` - Update dependencies
- `devenv info` - Show environment information

### Language ecosystem integration

devenv understands language-specific conventions and tooling. Instead of manually configuring build tools, package managers, and version managers, you enable a language module:

```nix
{
  languages.python = {
    enable = true;
    version = "3.11";
    venv.enable = true;  # Automatically create and manage virtualenv
    venv.requirements = ./requirements.txt;
  };
}
```

This sets up Python, creates a virtualenv, installs dependencies, and configures the environment—all declaratively.

## Difference from direnv

While both tools enhance development environments, they serve different purposes and can be used together.

### direnv: Environment loader

direnv is a shell extension that automatically loads environment variables and activates development shells when you `cd` into a directory. It's:

- **Lightweight**: Focuses on environment activation
- **Shell-agnostic**: Works with any shell (bash, zsh, fish)
- **Fast**: Caches environments for quick activation
- **Passive**: Only loads environments; doesn't manage services

### devenv: Development environment manager

devenv is a complete development environment toolkit. It:

- **Manages services**: Starts databases, web servers, background workers
- **Configures languages**: Sets up language-specific tooling
- **Runs processes**: Built-in process manager for multi-service development
- **Provides workflows**: Commands for testing, building, updating

### Using them together

devenv and direnv complement each other. Use devenv to define your environment and services, then use direnv to automatically activate it:

```nix
# devenv.nix
{
  languages.javascript.enable = true;
  services.postgres.enable = true;
}
```

```bash
# .envrc
use devenv
```

Now `cd`-ing into the directory automatically activates the devenv environment through direnv.

## Unique features of devenv

### Service lifecycle management

devenv includes process-compose for managing service lifecycles. Define services in your configuration:

```nix
{
  services.postgres = {
    enable = true;
    listen_addresses = "127.0.0.1";
    port = 5432;
  };

  services.redis = {
    enable = true;
    port = 6379;
  };

  processes = {
    web-server = {
      exec = "npm run dev";
    };

    worker = {
      exec = "npm run worker";
    };
  };
}
```

Start everything with `devenv up`. Services start in dependency order with proper health checks.

### Pre-commit hooks integration

devenv integrates with pre-commit hooks out of the box:

```nix
{
  pre-commit.hooks = {
    nixpkgs-fmt.enable = true;
    prettier.enable = true;
    eslint.enable = true;
  };
}
```

Hooks install automatically when entering the environment and run before commits.

### Container generation

Generate OCI containers from your devenv configuration:

```bash
devenv container
```

This creates a container image with your entire development environment, useful for CI/CD or sharing environments with teammates who prefer containers.

### Scripts and tasks

Define project-specific scripts in your configuration:

```nix
{
  scripts = {
    setup.exec = ''
      echo "Setting up project..."
      npm install
      devenv up -d
      npm run migrate
    '';

    test.exec = ''
      npm run test
    '';

    deploy.exec = ''
      echo "Deploying..."
      npm run build
      # deployment logic
    '';
  };
}
```

Run them with `devenv run setup`, `devenv run test`, etc.

### Environment info and debugging

devenv provides introspection commands:

```bash
# Show all environment variables
devenv info

# Show service status
devenv status

# Generate shell completion
devenv shell --print-dev-env
```

These help debug environment issues and understand what's configured.

## Common example

### Full-stack web application

A typical web application with Node.js, PostgreSQL, and Redis:

```nix
{ pkgs, ... }:

{
  # Language configuration
  languages = {
    javascript = {
      enable = true;
      package = pkgs.nodejs;
    };
  };

  # Services
  services = {
    postgres = {
      enable = true;
      initialDatabases = [{ name = "myapp_dev"; }];
      initialScript = ''
        CREATE USER myapp WITH PASSWORD 'dev';
        GRANT ALL PRIVILEGES ON DATABASE myapp_dev TO myapp;
      '';
    };

    redis = {
      enable = true;
    };
  };

  # Processes
  processes = {
    web = {
      exec = "npm run dev";
    };

    worker = {
      exec = "npm run worker";
    };
  };

  # Environment variables
  env = {
    DATABASE_URL = "postgresql://myapp:dev@localhost/myapp_dev";
    REDIS_URL = "redis://localhost:6379";
    NODE_ENV = "development";
  };

  # Development packages
  packages = with pkgs; [
    postgresql  # For psql client
    redis       # For redis-cli
  ];

  # Scripts
  scripts = {
    setup.exec = ''
      npm install
      npm run migrate
    '';

    reset-db.exec = ''
      dropdb --if-exists myapp_dev
      createdb myapp_dev
      npm run migrate
    '';
  };

  # Pre-commit hooks
  pre-commit.hooks = {
    prettier.enable = true;
    eslint.enable = true;
  };

  # Enter shell message
  enterShell = ''
    echo "🚀 Development environment ready!"
    echo "Run 'devenv up' to start all services"
    echo "Run 'devenv run setup' to initialize the project"
  '';
}
```

Workflow:

```bash
# First time setup
devenv shell
devenv run setup

# Daily development
devenv up  # Starts postgres, redis, web server, and worker

# In another terminal
devenv shell
npm run test

# Reset database
devenv run reset-db
```

### Python data science environment

A data science project with Python, Jupyter, and PostgreSQL:

```nix
{ pkgs, ... }:

{
  languages.python = {
    enable = true;
    version = "3.11";
    venv = {
      enable = true;
      requirements = ''
        jupyter
        pandas
        numpy
        matplotlib
        psycopg2-binary
        sqlalchemy
      '';
    };
  };

  services.postgres = {
    enable = true;
    initialDatabases = [{ name = "data_analysis"; }];
  };

  processes.jupyter = {
    exec = "jupyter lab --ip=0.0.0.0 --port=8888";
  };

  env = {
    DATABASE_URL = "postgresql://localhost/data_analysis";
  };

  packages = with pkgs; [
    postgresql  # psql client
  ];

  scripts = {
    notebook.exec = "jupyter lab";

    load-data.exec = ''
      python scripts/load_sample_data.py
    '';
  };

  enterShell = ''
    echo "📊 Data science environment ready"
    echo "Python $(python --version)"
    echo "Run 'devenv up' to start Jupyter and PostgreSQL"
  '';
}
```

### Rust project with database

A Rust application with PostgreSQL for integration tests:

```nix
{ pkgs, ... }:

{
  languages.rust = {
    enable = true;
    channel = "stable";
  };

  services.postgres = {
    enable = true;
    initialDatabases = [
      { name = "myapp_dev"; }
      { name = "myapp_test"; }
    ];
  };

  env = {
    DATABASE_URL = "postgresql://localhost/myapp_dev";
    TEST_DATABASE_URL = "postgresql://localhost/myapp_test";
  };

  packages = with pkgs; [
    postgresql
    sqlx-cli  # Database migration tool
  ];

  scripts = {
    migrate.exec = "sqlx migrate run";

    test.exec = ''
      sqlx database reset -y --database-url $TEST_DATABASE_URL
      cargo test
    '';

    dev.exec = "cargo watch -x run";
  };

  pre-commit.hooks = {
    rustfmt.enable = true;
    clippy.enable = true;
  };

  processes = {
    api = {
      exec = "cargo run";
    };
  };

  enterShell = ''
    echo "🦀 Rust development environment"
    rustc --version
    cargo --version
  '';
}
```

## Common issues

### Services fail to start

When `devenv up` fails to start services, check the logs for specific error messages. Services might fail due to:

- Port conflicts with existing processes
- Missing initialization or migration steps
- Incorrect configuration

View detailed service output:

```bash
devenv up --verbose
```

Check if ports are already in use:

```bash
lsof -i :5432  # Check PostgreSQL default port
lsof -i :6379  # Check Redis default port
```

Stop conflicting services or change ports in your devenv configuration:

```nix
{
  services.postgres.port = 5433;  # Use different port
  services.redis.port = 6380;
}
```

### Environment not updating after changes

After modifying `devenv.nix`, the environment might not reflect changes immediately. devenv caches evaluations for performance, so you need to reload:

```bash
# Exit and re-enter the shell
exit
devenv shell

# Or reload within the shell
direnv reload  # if using direnv
```

For service changes, restart them:

```bash
# Stop services
Ctrl+C  # in devenv up terminal

# Restart
devenv up
```

### Python venv issues

When using Python's venv integration, dependencies might not install correctly or the virtualenv might get corrupted. This often happens after changing `requirements.txt` or Python version. Regenerate the virtualenv:

```bash
# Remove existing venv
rm -rf .devenv

# Re-enter shell to recreate
exit
devenv shell
```

devenv creates a new virtualenv and installs dependencies fresh.

### Slow shell activation

First-time activation can be slow as devenv builds the environment and installs packages. Subsequent activations are much faster due to caching. For very slow environments, check if:

- You're building packages from source unnecessarily
- Large dependencies are being downloaded
- Many pre-commit hooks are installing

Use binary caches to avoid building from source:

```nix
{
  # Use cachix for faster package downloads
  cachix = {
    enable = true;
    caches = [ "devenv" ];
  };
}
```

### Permission errors with services

Service data directories sometimes have permission issues, especially when switching between different configurations. The `.devenv` directory stores service data and might have incorrect permissions. Clear the state:

```bash
rm -rf .devenv/state
devenv up
```

Services recreate their data directories with correct permissions.

### Pre-commit hooks not running

When pre-commit hooks aren't executing on commit, they might not be installed. devenv installs hooks automatically, but only within the development shell. Ensure you're committing from within the devenv shell:

```bash
devenv shell
git commit  # Hooks run here
```

Or explicitly install hooks:

```bash
devenv shell
pre-commit install
```

### Process crashes immediately

If a process defined in `processes` crashes immediately when running `devenv up`, check the command is correct and dependencies are available. Add debugging output to the exec command:

```nix
{
  processes.web = {
    exec = ''
      echo "Starting web server..."
      set -x  # Enable debug output
      npm run dev
    '';
  };
}
```

View the full output when running `devenv up` to see what's failing.

### Conflicting package versions

Multiple services or language configurations might pull in conflicting package versions. devenv tries to resolve these, but sometimes manual intervention is needed. Override specific packages:

```nix
{ pkgs, ... }:

{
  languages.python.enable = true;

  # Override a specific package
  packages = with pkgs; [
    (python311.withPackages (ps: with ps; [
      # Specific versions
      django_4
      psycopg2
    ]))
  ];
}
```

### Database initialization failures

When PostgreSQL or other database services fail during initialization, often the initial script has errors or the database already exists. Check initialization logs:

```bash
devenv up --verbose
```

Clear the database state and retry:

```bash
rm -rf .devenv/state/postgres
devenv up
```

The database recreates from scratch with your `initialScript` or `initialDatabases` configuration.

## Integration patterns

### With direnv

Automatically activate devenv when entering the directory:

```bash
# .envrc
use devenv
```

This combines direnv's automatic activation with devenv's full environment management.

### With CI/CD

Use devenv in CI to get identical environments:

```yaml
# GitHub Actions example
- uses: cachix/install-nix-action@v22

- name: Install devenv
  run: nix-env -iA devenv -f https://install.devenv.sh/latest

- name: Run tests
  run: devenv test
```

Or generate a container:

```bash
devenv container
# Use the generated container in CI
```

### With Docker for production

While devenv excels at development, you might still use Docker for production. Generate a devenv container for dev/prod parity:

```nix
{
  containers.app = {
    name = "myapp";
    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      paths = [ pkgs.nodejs ];
    };
    config = {
      Cmd = [ "npm" "start" ];
    };
  };
}
```

Build and run:

```bash
devenv container
docker load < ./result
docker run myapp
```

## Best practices

### Keep devenv.nix focused

Use `devenv.nix` for environment configuration and keep application logic in standard build files:

```nix
# Good: Environment only
{
  languages.javascript.enable = true;
  services.postgres.enable = true;
}

# Less good: Mixing app logic
{
  languages.javascript.enable = true;
  scripts.complex-app-build.exec = ''
    # 100 lines of application-specific build logic
  '';
}
```

Application builds belong in `package.json`, `Makefile`, or similar.

### Use scripts for common tasks

Define frequently-used commands as scripts:

```nix
{
  scripts = {
    db-reset.exec = "dropdb myapp && createdb myapp && migrate";
    test-watch.exec = "npm test -- --watch";
    lint.exec = "npm run lint && cargo clippy";
  };
}
```

This documents common workflows and makes them easily discoverable for team members.

### Version control devenv.lock

devenv generates a `devenv.lock` file pinning all dependencies. Commit this file to ensure reproducibility:

```bash
git add devenv.nix devenv.lock
git commit -m "Add devenv configuration"
```

### Document the environment

Use `enterShell` to show helpful information:

```nix
{
  enterShell = ''
    cat <<EOF
    🎯 Project Development Environment

    Available commands:
      devenv up         - Start all services
      devenv run setup  - Initialize project
      devenv run test   - Run tests

    Services:
      PostgreSQL - localhost:5432
      Redis      - localhost:6379

    Documentation: https://github.com/myorg/myproject/wiki/dev-setup
    EOF
  '';
}
```

### Layer environments carefully

For complex projects with multiple environments (dev, test, staging), use composition:

```nix
# devenv.nix (base config)
{ pkgs, ... }:
{
  imports = [ ./devenv-base.nix ];

  # Development-specific
  services.postgres.initialDatabases = [{ name = "myapp_dev"; }];
}
```

```nix
# devenv-test.nix
{ pkgs, ... }:
{
  imports = [ ./devenv-base.nix ];

  # Test-specific
  services.postgres.initialDatabases = [{ name = "myapp_test"; }];
}
```

## Further reading

- [devenv documentation](https://devenv.sh/)
- [devenv examples](https://devenv.sh/examples/)
- [Language integrations](https://devenv.sh/languages/)
- [Services reference](https://devenv.sh/services/)

devenv brings the convenience of tools like docker-compose to Nix development environments while maintaining reproducibility and the full power of nixpkgs.
