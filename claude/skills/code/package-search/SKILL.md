---
name: package-search
description: Search for installed packages on local machine before fetching from external sources. Use when user asks about a package, library, or dependency to explore its code, understand its API, or debug issues.
---

# Package Search Skill

Use this skill when the user asks about a package, library, or dependency. **Always search for it on the local machine first** before trying to fetch from git, documentation sites, or the web.

## Core Principle

**Local-first package exploration**: The user's machine likely has the exact version they're using installed locally. This is:
- **Faster** than fetching from external sources
- **More accurate** (matches their actual version)
- **More complete** (includes all implementation details)
- **Works offline**

## Workflow

### 1. Determine Package Type and Location

Common package locations by language/ecosystem:

- **Python**: `.venv/`, `~/.local/lib/python*/site-packages/`, virtualenv locations
- **Node/JS**: `node_modules/`, `~/.npm/`, `/usr/local/lib/node_modules/`
- **Neovim plugins**: `~/.local/share/nvim/lazy/`, `~/.local/share/nvim/site/pack/`
- **Ruby**: `~/.gem/`, `/usr/local/lib/ruby/gems/`
- **Rust**: `~/.cargo/registry/src/`

For language-specific search strategies, see the language skills:
- [Python skill](../../language/python/SKILL.md)
- [Neovim skill](../../language/neovim/SKILL.md)

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

Once found:

```bash
# List structure
fd -t f . /path/to/package | head -20

# Find entry points
fd -t f "(^__init__|^index|^lib|^main)" /path/to/package

# Search for specific functionality (use rg for simple text search)
rg "class ClassName" /path/to/package
rg "def function_name" /path/to/package
```

### 4. Advanced Code Searching with ast-grep

For **structural code search** (when you need to understand syntax, not just text), use `sg` (ast-grep):

**When to use ast-grep over ripgrep:**
- Finding function/class definitions with specific signatures
- Searching for patterns with variable names you don't know
- Finding all usages of a specific API pattern
- Understanding complex nested structures

**Common ast-grep patterns:**

```bash
# Find all function definitions (Python)
sg -p 'def $FUNC($$$):' /path/to/package

# Find class definitions with inheritance
sg -p 'class $CLASS($BASE):' /path/to/package

# Find all function calls to a specific function (any arguments)
sg -p 'function_name($$$)' /path/to/package

# Find try-except blocks (Python)
sg -p 'try: $$$' /path/to/package

# Find all React components (TypeScript/JSX)
sg -p 'function $NAME(): JSX.Element { $$$ }' /path/to/package

# Find all exports (JavaScript)
sg -p 'export const $NAME = $$$' /path/to/package

# Find Lua function definitions with specific pattern
sg -p 'function M.$METHOD($$$) $$$ end' /path/to/package
```

**ast-grep is especially useful for:**
- Finding all implementations of an interface/base class
- Locating specific API usage patterns
- Understanding how a package structures its exports
- Finding callback patterns or specific syntax constructs

**Example: Understanding how a package exports its API**
```bash
# Python: Find all public functions (no leading underscore)
sg -p 'def $FUNC($$$):' /path/to/package --json | jq '.[] | select(.name | test("^[^_]"))'

# JavaScript: Find all named exports
sg -p 'export function $NAME($$$) { $$$ }' /path/to/package
sg -p 'export const $NAME = $$$' /path/to/package
```

### 5. Read Relevant Files

Use the Read tool to examine:
- Entry points (`__init__.py`, `index.js`, `init.lua`, etc.)
- Specific modules the user asks about
- Type definitions (`.pyi`, `.d.ts` files)
- Documentation (`README.md`, `CHANGELOG.md`)

## Quick Examples

**Find Python package:**
```bash
python -c "import requests; print(requests.__file__)"
rg "timeout" /path/to/requests
sg -p 'def request($$$):' /path/to/requests  # Find request function definition
```

**Find Neovim plugin:**
```bash
fd -t d "tokyonight" ~/.local/share/nvim/lazy
rg "function.*setup" ~/.local/share/nvim/lazy/tokyonight.nvim
sg -p 'M.setup = function($$$) $$$ end' ~/.local/share/nvim/lazy/tokyonight.nvim
```

**Find Node package:**
```bash
fd -t d "^express$" node_modules
rg "export.*Router" node_modules/express
sg -p 'export class $NAME { $$$ }' node_modules/express
```

## When Local Search Fails

If the package isn't installed locally:

1. **Ask the user** if they want to install it first
2. **Check availability** in their package manager (`pip search`, `npm view`, etc.)
3. **Only then** fall back to:
   - Official documentation websites
   - GitHub repository (if user provides URL)
   - Package registry websites (PyPI, npm, etc.)

## Benefits of Local-First

- **Version accuracy**: Exact code they're running
- **Complete access**: Private methods, implementation, comments
- **Debugging ready**: Can trace through actual code
- **No network needed**: Works offline
- **Fast**: No download time

## Integration with Other Skills

- **Python**: See [python skill](../../language/python/SKILL.md) for Python package exploration
- **Neovim**: See [neovim skill](../../language/neovim/SKILL.md) for plugin exploration
- **Diagnostics**: Use [diagnostics skill](../diagnostics/SKILL.md) to check package issues

## Tools to Use

- **fd**: Fast file/directory finding
- **rg** (ripgrep): Fast text-based code searching
- **sg** (ast-grep): Structural code search (syntax-aware)
- **Read tool**: Reading specific files
- **Bash tool**: Running package introspection commands

## Further Reading

- [Development Workflow](../../../references/development.md)
- [Python Skill](../../language/python/SKILL.md)
- [Neovim Skill](../../language/neovim/SKILL.md)
