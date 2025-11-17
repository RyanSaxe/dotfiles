# Package Search Skill

---
name: package-search
description: Search for installed packages on local machine before fetching from external sources. Use when user asks about a package, library, or dependency to explore its code, understand its API, or debug issues.
---

## Quick Reference

**Always search locally first:**
```bash
# Python
python -c "import pkg; print(pkg.__file__)"
fd -t d "^package$" .venv/lib/python*/site-packages/

# Node
fd -t d "^package$" node_modules/

# Neovim
fd -t d "plugin-name" ~/.local/share/nvim/lazy/
```

**Tools:**
- `fd` - Fast directory search
- `rg` - Text-based code search
- `sg` (ast-grep) - Structural code search

**Related:**
- [ast-grep guide](../../../references/tools/ast-grep.md) - Structural search patterns
- Language skills - Package locations and patterns

---

## Core Principle: Local-First

**Always search for packages on the local machine first** before fetching from external sources.

**Why local-first:**
- **Faster** than external sources
- **More accurate** (matches their actual version)
- **More complete** (includes all implementation details)
- **Works offline**
- **Version accuracy** - exact code they're running

---

## Workflow

### 1. Determine Package Location

Common package locations by ecosystem:

- **Python**: `.venv/`, `~/.local/lib/python*/site-packages/`, virtualenv locations
- **Node/JS**: `node_modules/`, `~/.npm/`, `/usr/local/lib/node_modules/`
- **Neovim plugins**: `~/.local/share/nvim/lazy/`, `~/.local/share/nvim/site/pack/`
- **Ruby**: `~/.gem/`, `/usr/local/lib/ruby/gems/`
- **Rust**: `~/.cargo/registry/src/`

For language-specific strategies, see `skills/language/` - Claude will auto-invoke the relevant language skill.

### 2. Search for Package

```bash
# Fast targeted search with fd
fd -t d "^package_name$" /likely/base/path

# Broader search if not found
fd -t d "package_name" /broader/path

# Last resort: search home directory (slow)
fd -t d "package_name" ~
```

### 3. Explore Package Contents

```bash
# List structure
fd -t f . /path/to/package | head -20

# Find entry points
fd -t f "(^__init__|^index|^lib|^main)" /path/to/package

# Search for specific functionality
rg "class ClassName" /path/to/package
rg "def function_name" /path/to/package
```

### 4. Structural Code Search (ast-grep)

For **structural patterns** (not just text), use `sg` (ast-grep):

```bash
# Find function definitions (Python)
sg -p 'def $FUNC($$$):' /path/to/package

# Find class definitions with inheritance
sg -p 'class $CLASS($BASE):' /path/to/package

# Find all function calls (any arguments)
sg -p 'function_name($$$)' /path/to/package

# Find exports (JavaScript)
sg -p 'export const $NAME = $$$' /path/to/package
```

**When to use ast-grep:**
- Finding function/class definitions with specific signatures
- Searching for patterns with unknown variable names
- Finding all usages of a specific API pattern
- Understanding complex nested structures

[Complete ast-grep patterns →](../../../references/tools/ast-grep.md)

### 5. Read Relevant Files

Use Read tool to examine:
- Entry points (`__init__.py`, `index.js`, `init.lua`)
- Specific modules the user asks about
- Type definitions (`.pyi`, `.d.ts` files)
- Documentation (`README.md`, `CHANGELOG.md`)

---

## Quick Examples by Language

### Python Package

```bash
python -c "import requests; print(requests.__file__)"
rg "timeout" /path/to/requests
sg -p 'def request($$$):' /path/to/requests
```

### Neovim Plugin

```bash
fd -t d "tokyonight" ~/.local/share/nvim/lazy
rg "function.*setup" ~/.local/share/nvim/lazy/tokyonight.nvim
sg -p 'M.setup = function($$$) $$$ end' ~/.local/share/nvim/lazy/tokyonight.nvim
```

### Node Package

```bash
fd -t d "^express$" node_modules
rg "export.*Router" node_modules/express
sg -p 'export class $NAME { $$$ }' node_modules/express
```

---

## When Local Search Fails

If the package isn't installed locally:

1. **Ask the user** if they want to install it first
2. **Check availability** in their package manager
   - Python: `pip search` or `uv search`
   - Node: `npm view`
   - Neovim: Check package manager (lazy.nvim, packer)
3. **Only then** fall back to:
   - Official documentation websites
   - GitHub repository (if user provides URL)
   - Package registry websites (PyPI, npm, etc.)

---

## Benefits of Local-First

- **Version accuracy**: Exact code they're running
- **Complete access**: Private methods, implementation, comments
- **Debugging ready**: Can trace through actual code
- **No network needed**: Works offline
- **Fast**: No download time
- **Trust**: Code is already on their machine

---

## Tools Summary

- **fd**: Fast file/directory finding (use this, not `find`)
- **rg** (ripgrep): Fast text-based code searching (use this, not `grep`)
- **sg** (ast-grep): Structural code search (syntax-aware) - [full guide](../../../references/tools/ast-grep.md)
- **Read tool**: Reading specific files
- **Bash tool**: Running package introspection commands

---

## Related Resources

- [ast-grep guide](../../../references/tools/ast-grep.md) - Complete structural search patterns
- [Python skill](../lang-python/SKILL.md) - Python package exploration
- [Neovim skill](../lang-neovim/SKILL.md) - Plugin exploration
- [Development workflow](../../../references/development.md) - Development process
