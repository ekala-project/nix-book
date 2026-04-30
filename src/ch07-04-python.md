# Python

Python packaging in Nix requires special consideration due to how Python finds and loads
modules. Unlike compiled languages where dependencies are linked at build time, Python
searches for modules at runtime in specific directories. This generally is handled
by `buildPythonPackage` and `buildPythonApplication` gracefully, but can cause some
issues in various situations.

## Python and Nix: special concerns

### Module discovery and site-packages

Traditional Python installations place packages in a shared `site-packages` directory
(e.g., `/usr/lib/python3.11/site-packages`). When you import a module, Python searches
these standard locations.

Nix takes a different approach:
- Each package has its own isolated store path
- Python packages are installed to `$out/lib/python3.X/site-packages/`
- Dependencies aren't automatically visible to Python programs

To solve this, Nix uses wrapper scripts that set `PYTHONPATH` to include all dependencies,
or builds Python environments that aggregate packages into a single site-packages directory.

### Import-time vs runtime dependencies

Python has a unique characteristic where imports can happen at any point during execution,
not just at program startup. This means:
- All Python dependencies must be available in `PYTHONPATH`
- Missing dependencies only manifest when code tries to import them
- Optional dependencies may only be discovered during specific code paths

## Basic Python package

Python packages in nixpkgs use `buildPythonPackage` from the Python package set. Here's
a minimal example:

```nix
{ lib, buildPythonPackage, fetchPypi }:

buildPythonPackage rec {
  pname = "requests";
  version = "2.31.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-lC8FSGGo...";
  };

  meta = with lib; {
    description = "Python HTTP for Humans";
    homepage = "https://requests.readthedocs.io";
    license = licenses.asl20;
  };
}
```

The `buildPythonPackage` function automatically handles:
- Running `python setup.py`, `pip install`, `poetry install`, and other installers.
- Installing to the correct `site-packages` directory
- Generating wrapper scripts with proper `PYTHONPATH`
- Managing Python version compatibility

## buildPythonPackage vs buildPythonApplication

Nixpkgs provides two main functions for Python projects:

### buildPythonPackage

Use for Python libraries that other Python packages depend on.

Packages built with `buildPythonPackage`:
- Are included in Python environments via `python.withPackages`
- Can be used as dependencies by other Python packages
- Are installed into `site-packages`

### buildPythonApplication

Use for end-user Python applications with executable scripts, and not to be used as a module:

```nix
{ lib, buildPythonApplication, fetchPypi, requests, click }:

buildPythonApplication rec {
  pname = "myapp";
  version = "2.0.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "...";
  };

  propagatedBuildInputs = [ requests click ];

  meta = with lib; {
    description = "A Python application";
    license = licenses.gpl3;
    mainProgram = "myapp";
  };
}
```

Packages built with `buildPythonApplication`:
- Are meant to be installed directly into user profiles
- Cannot be used as dependencies by other Python packages
- Have stricter dependency isolation to prevent conflicts

**Rule of thumb:** If your package provides a library that others import, use
`buildPythonPackage`. If it's primarily a command-line tool or standalone application,
use `buildPythonApplication`.

## Build formats and pyproject

Python has evolved through several packaging standards:

1. **setup.py** (legacy): Imperative Python script
2. **setup.cfg** (transitional): Declarative configuration
3. **pyproject.toml** (modern): Standard metadata format (PEP 517/518)

### pyproject = true

Modern Python packages use `pyproject.toml` with PEP 517 build backends. Enable this
with `pyproject = true`:

```nix
{ lib, buildPythonPackage, fetchPypi, setuptools }:

buildPythonPackage rec {
  pname = "modern-package";
  version = "3.0.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    sha256 = "...";
  };

  nativeBuildInputs = [ setuptools ];

  meta = with lib; {
    description = "A modern Python package using pyproject.toml";
    license = licenses.mit;
  };
}
```

When `pyproject = true`:
- The build backend (setuptools, poetry-core, hatchling, etc.) must be in `nativeBuildInputs`
- Nix uses PEP 517 compliant build process
- No `setup.py` is required

### Common build backends

**setuptools** (most common):
```nix
nativeBuildInputs = [ setuptools ];
```

**poetry-core** (for Poetry projects):
```nix
nativeBuildInputs = [ poetry-core ];
```

**hatchling** (for Hatch projects):
```nix
nativeBuildInputs = [ hatchling ];
```

**flit-core** (for Flit projects):
```nix
nativeBuildInputs = [ flit-core ];
```

## Common configuration options

### Dependencies

**propagatedBuildInputs**: Runtime dependencies (libraries your package imports)
```nix
propagatedBuildInputs = [ requests numpy pandas ];
```

**nativeBuildInputs**: Build-time tools (build backends, etc.)
```nix
nativeBuildInputs = [ setuptools wheel ];
```

**checkInputs**: Test-only dependencies
```nix
checkInputs = [ pytest pytest-cov ];
```

### Format specification

For older packages not using pyproject.toml:

```nix
# For setup.py based packages (default)
format = "setuptools";

# For packages with just a .whl wheel
format = "wheel";

# For other formats
format = "other";
```

### Disabling tests

```nix
# Don't run tests at all
doCheck = false;

# Disable only some tests
checkInputs = [ pytestCheckHook ];
disabledTests = [ "network" ];
```

### Python version constraints

The `disabled` attr can be used to throw an evaluation error, thus making the
usage fail quicker for the user.

```nix
{ lib, buildPythonPackage, fetchPypi, pythonOlder }:

buildPythonPackage rec {
  pname = "modern-package";
  version = "1.0.0";

  # Disable for Python < 3.8
  disabled = pythonOlder "3.8";

  # ...
}
```

## Common issues and fixes

### Missing dependencies

If imports fail at runtime, add the dependency to `propagatedBuildInputs`:

```nix
propagatedBuildInputs = [ missing-module ];
```

Note: `buildInputs` doesn't work for Python packages - always use `propagatedBuildInputs`
for runtime dependencies.

### Test failures

Disable problematic tests:

```nix
checkPhase = ''
  # Skip specific tests
  pytest -k "not test_problematic"

  # Skip entire test files
  pytest --ignore=tests/test_network.py
'';
```

Or disable all tests:

```nix
doCheck = false;
```

### Build backend not found

Modern packages need their build backend specified:

```nix
pyproject = true;
nativeBuildInputs = [ setuptools ];  # or poetry-core, hatchling, etc.
```

### Import errors for C extensions

Some packages build C extensions and need build dependencies:

```nix
{ lib, buildPythonPackage, fetchPypi, libxml2, libxslt }:

buildPythonPackage rec {
  pname = "lxml";
  version = "4.9.3";

  src = fetchPypi {
    inherit pname version;
    sha256 = "...";
  };

  buildInputs = [ libxml2 libxslt ];

  meta = with lib; {
    description = "Python bindings for libxml2 and libxslt";
    license = licenses.bsd3;
  };
}
```

### Optional dependencies

Some packages have optional feature sets. Use `passthru.optional-dependencies`:

```nix
propagatedBuildInputs = [ core-dep ];

passthru.optional-dependencies = {
  dev = [ pytest mypy ];
  docs = [ sphinx ];
};
```

### Packages not in PyPI

For packages not on PyPI, use `fetchFromGitHub`:

```nix
{ lib, buildPythonPackage, fetchFromGitHub, setuptools }:

buildPythonPackage rec {
  pname = "custom-package";
  version = "1.0.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "user";
    repo = "custom-package";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [ setuptools ];

  meta = with lib; {
    description = "Custom package from GitHub";
    license = licenses.mit;
  };
}
```

### Setup requires

Some packages declare build dependencies in `setup_requires` which Nix doesn't handle
automatically. Add them to `nativeBuildInputs`:

```nix
nativeBuildInputs = [ setuptools setuptools-scm wheel ];
```

## Detailed example

Here's a comprehensive example of a Python application with multiple dependencies,
tests, and modern packaging:

```nix
{ lib
, buildPythonApplication
, fetchFromGitHub
, pythonOlder
# Build dependencies
, setuptools
, setuptools-scm
# Runtime dependencies
, click
, requests
, pyyaml
, rich
, sqlalchemy
# Test dependencies
, pytest
, pytest-cov
, pytest-mock
, pytestCheckHook
}:

buildPythonApplication rec {
  pname = "example-cli-tool";
  version = "2.5.0";
  pyproject = true;

  # Require Python 3.9 or newer
  disabled = pythonOlder "3.9";

  src = fetchFromGitHub {
    owner = "example";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Needed because project uses setuptools-scm for version detection
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  nativeBuildInputs = [
    setuptools
    setuptools-scm
  ];

  propagatedBuildInputs = [
    click
    requests
    pyyaml
    rich
    sqlalchemy
  ];

  nativeCheckInputs = [
    pytest
    pytest-cov
    pytest-mock
    pytestCheckHook
  ];

  # Set pytest flags
  pytestFlagsArray = [
    "-v"
    "--cov=${pname}"
    "--cov-report=term-missing"
  ];

  # Disable specific tests that require network or are flaky
  disabledTests = [
    "test_api_connection"
    "test_downloads_file"
  ];

  # Skip entire test modules
  disabledTestPaths = [
    "tests/integration/"
  ];

  pythonImportsCheck = [
    "example_cli_tool"
    "example_cli_tool.commands"
  ];

  meta = with lib; {
    description = "Example CLI tool for managing workflows";
    longDescription = ''
      A comprehensive command-line tool demonstrating best practices
      for Python applications in nixpkgs, including proper dependency
      management, testing, and packaging.
    '';
    homepage = "https://github.com/example/example-cli-tool";
    changelog = "https://github.com/example/example-cli-tool/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    mainProgram = "example-cli";
  };
}
```

This example demonstrates:
- Using `buildPythonApplication` for a CLI tool
- Modern `pyproject = true` packaging
- Python version constraints
- Build backend configuration (setuptools-scm)
- Clear separation of build, runtime, and test dependencies
- Comprehensive test configuration with pytestCheckHook
- Selective test disabling
- Import checks for basic validation
- Complete metadata including changelog

## Creating Python environments

To use multiple Python packages together, create an environment. This is similar
to using virtualenv:

```nix
# In a shell.nix or similar
{ pkgs ? import <nixpkgs> {} }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    requests
    numpy
    pandas
    matplotlib
  ]);
in
pkgs.mkShell {
  buildInputs = [ pythonEnv ];
}
```

This creates a Python environment with all specified packages available for import.

## Summary

Python packaging in Nix requires understanding module resolution and isolation:
- Use `buildPythonPackage` for libraries, `buildPythonApplication` for applications
- Set `pyproject = true` for modern packages using pyproject.toml
- Always use `propagatedBuildInputs` for runtime Python dependencies
- Specify the build backend in `nativeBuildInputs` (setuptools, poetry-core, etc.)
- Use `pytestCheckHook` for comprehensive test integration
- Check existing nixpkgs Python packages for patterns and examples
