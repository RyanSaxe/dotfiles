# uv - Python Package and Environment Manager

`uv` is an extremely fast Python package installer and resolver, written in
Rust. It's used for dependency management, virtual environments, and running
Python tools.

## Quick Reference

**Most common commands:**

```bash
uvx <tool>              # Run tool without installing (e.g., uvx ruff check .)
uv add <package>        # Add dependency
uv sync                 # Sync environment from lock file
uv run <command>        # Run command in project environment
uv venv                 # Create virtual environment
```

**Related:**

- [Python skill](../../skills/language/python/SKILL.md) - Python-specific usage
  patterns
- [Official uv docs](https://github.com/astral-sh/uv)
- [PEP 723 - Inline script metadata](https://peps.python.org/pep-0723/)

---

## Core Commands

### Virtual Environments

```bash
# Create virtual environment
uv venv

# Create with specific Python version
uv venv --python 3.12

# Sync dependencies from pyproject.toml
uv sync

# Sync with specific groups
uv sync --group dev
```

### Dependency Management

```bash
# Add dependency
uv add requests

# Add dev dependency
uv add --dev pytest

# Add with version constraint
uv add "pandas>=2.0.0"

# Remove dependency
uv remove requests

# Update dependencies
uv lock --upgrade
```

### Running Tools Without Installation (uvx)

**This is incredibly useful for Claude Code!** `uvx` allows running Python tools
without installing them globally:

```bash
# Run a tool without installing it
uvx ruff check .
uvx black --check .
uvx mypy src/

# Run specific version
uvx ruff@0.1.0 check .

# Pass arguments
uvx httpie GET https://api.example.com

# Run with dependencies
uvx --with pandas python -c "import pandas; print(pandas.__version__)"
```

**Benefits:**

- No global installation clutter
- Always use latest version (or specify version)
- Works in any directory
- Perfect for one-off operations
- Isolates tool dependencies

**Common use cases for Claude:**

```bash
# Format code without installing formatter
uvx black .

# Run linters
uvx ruff check .
uvx mypy src/

# Run tools for specific tasks
uvx httpie GET https://api.example.com/data
uvx jq '.results' data.json

# Try out packages
uvx ipython  # Interactive Python shell with IPython
```

## Python Scripts with Inline Dependencies (PEP 723)

`uv` supports inline script dependencies, allowing self-contained Python
scripts:

### Creating a Script

```bash
# Create script file
cat > script.py << 'EOF'
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

def main():
    print("Hello, world!")

if __name__ == "__main__":
    main()
EOF

# Make executable
chmod +x script.py

# Run with uv
uv run script.py

# Or if executable with shebang
./script.py
```

### Adding Dependencies to Scripts

```bash
# Add dependencies using uv
uv add --script script.py pandas numpy requests

# Specify version constraints
uv add --script script.py "pandas>=2.0.0"
```

### Script Dependency Block Format

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pandas>=2.0.0",
#     "numpy",
#     "requests",
#     "click>=8.0",
# ]
# ///

import pandas as pd
import numpy as np
import requests
import click

@click.command()
def main():
    """Your script logic here."""
    pass

if __name__ == "__main__":
    main()
```

**Key points:**

- Shebang line: `#!/usr/bin/env -S uv run`
- Dependency block between `# /// script` and `# ///`
- Specify Python version requirement
- List dependencies with optional version constraints
- `uv run` automatically creates isolated environment and installs dependencies

### Running Scripts

```bash
# With uv run
uv run script.py

# If executable with shebang
./script.py

# Pass arguments
uv run script.py --arg value
./script.py --arg value
```

## Project Environment Workflows

### New Project

```bash
# Initialize new project
uv init myproject
cd myproject

# Create virtual environment
uv venv

# Add dependencies
uv add requests pandas

# Add dev dependencies
uv add --dev pytest ruff black

# Sync environment
uv sync
```

### Existing Project

```bash
# Sync from lock file
uv sync

# Or from pyproject.toml (creates new lock)
uv lock
uv sync

# Activate venv (if needed)
source .venv/bin/activate
```

### Running Commands in Project

```bash
# Run Python in project environment
uv run python script.py

# Run tests
uv run pytest

# Run tools
uv run black .
uv run ruff check .
```

## Integration with Skills

### For Standalone Scripts

When creating reusable scripts within skills:

1. Use `#!/usr/bin/env -S uv run` shebang
2. Add inline dependency block
3. Use `uv add --script` to manage dependencies
4. Make executable with `chmod +x`

**Example:**

```bash
# Create skill script
cat > scripts/process_data.py << 'EOF'
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pandas>=2.0.0",
# ]
# ///

import pandas as pd

def main():
    df = pd.read_csv("data.csv")
    print(df.describe())

if __name__ == "__main__":
    main()
EOF

chmod +x scripts/process_data.py
uv add --script scripts/process_data.py pandas
```

### For Project Work

When working in a Python project:

1. Check for existing `pyproject.toml` or `uv.lock`
2. Use `uv sync` to set up environment
3. Use `uv run` to execute commands in project context
4. Add dependencies with `uv add`

## Comparison with Other Tools

### vs pip

- Much faster (10-100x in many cases)
- Better dependency resolution
- Lock file support
- Integrated venv management

### vs poetry

- Faster
- Compatible with standard `pyproject.toml`
- Simpler mental model
- Better for monorepos

### vs pipx

- `uvx` is similar to `pipx` but faster
- Better isolation
- More flexible (can specify dependencies with `--with`)

## Common Workflows

### One-off Tool Execution

```bash
# Instead of: pip install tool && tool
# Use: uvx tool
uvx black .
```

### Project Dependency Management

```bash
# Add dependency
uv add requests

# Update dependencies
uv lock --upgrade
uv sync

# Check what would be updated
uv lock --upgrade --dry-run
```

### Running Tests

```bash
# In project
uv run pytest

# With coverage
uv run pytest --cov=mymodule
```

## Tips

1. **Use `uvx` for tools** - Don't install formatters, linters globally
2. **Lock files are important** - Commit `uv.lock` for reproducible builds
3. **Inline scripts for skills** - Make scripts self-contained with dependencies
4. **Fast sync** - `uv sync` is very fast, run often
5. **Version specificity** - Use `uvx tool@version` for specific versions
