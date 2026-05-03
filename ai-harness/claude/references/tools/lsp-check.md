# lsp-check - LSP Diagnostics Tool

Automated LSP diagnostic collection using headless Neovim. Opens files, triggers LSP servers, and collects diagnostics with smart settling logic.

## Quick Reference

**⚠️ IMPORTANT: Always run lsp-check on targeted files/folders, not entire repositories!**

**Most common commands:**

```bash
# Target specific files or directories you're working on
lsp-check src/mymodule/            # Check specific module
lsp-check src/main.py tests/       # Check specific files/dirs
lsp-check "src/**/*.py"            # Check with glob pattern

# Detailed output with filtering
lsp-check src/ --detailed          # Show all diagnostics
lsp-check src/ --min-severity ERROR # Only errors
lsp-check src/ --source pyright    # Filter by LSP source

# AVOID: Running on entire repo (includes dependencies, build artifacts, etc.)
# lsp-check .                      # ❌ DON'T DO THIS unless you really mean it
```

**Related:**

- [Diagnostics skill](../../skills/code/diagnostics/SKILL.md) - Workflow integration
- [Development workflow](../development.md) - How diagnostics fit into your process
- Script location: `~/generic/dotfiles/scripts/lsp-check`

---

## Purpose

- Opens files in headless Neovim to trigger LSP servers
- Collects diagnostics with smart settling (waits for diagnostic updates to stabilize)
- Outputs structured JSON + pretty-formatted results
- Supports filtering by severity and LSP source
- **Respects .gitignore by default** to avoid checking dependencies and build artifacts

## Basic Usage

### ⚠️ Always Target Specific Files/Folders

**Best practice:** Run lsp-check on the specific files or directories you're working on, not the entire repository. This avoids checking dependencies (node_modules, venv), build artifacts, and other irrelevant files.

```bash
# Good: Check specific module
lsp-check src/mymodule/

# Good: Check specific files
lsp-check src/main.py src/utils.py

# Good: Check multiple directories
lsp-check src/ tests/
```

### Check Entire Repository (Use With Caution)

Only use this when you specifically need to check everything:

```bash
# Checks all files respecting .gitignore (still may include many files)
lsp-check .

# Override .gitignore to check EVERYTHING (rarely needed)
lsp-check . --no-ignore
```

Output shows summary with top files containing issues.

### Detailed Diagnostics

```bash
lsp-check src/ --detailed
```

Shows all diagnostics file-by-file with:

- Color-coded severity (ERROR=red, WARN=yellow, INFO=blue, HINT=gray)
- Line and column numbers
- Diagnostic codes and sources
- Full diagnostic messages

### Filter by Severity

```bash
# Only errors in specific directory
lsp-check src/ --detailed --min-severity ERROR

# Warnings and errors (excludes info/hints)
lsp-check src/ --detailed --min-severity WARN
```

Severity levels (most to least severe): `ERROR` > `WARN` > `INFO` > `HINT`

### Filter by LSP Source

```bash
# Only pyright diagnostics in specific directory
lsp-check src/ --detailed --source pyright

# Only typescript diagnostics
lsp-check src/ --detailed --source typescript-language-server
```

### Check Specific Directories or Files

```bash
# Specific directory
lsp-check src/

# Multiple targets
lsp-check src/ tests/

# Specific file
lsp-check src/main.py

# Glob patterns (quote to prevent shell expansion)
lsp-check "src/**/*.py"
```

## Advanced Options

### Gitignore Control

```bash
# Default: respects .gitignore (excludes dependencies, build artifacts)
lsp-check src/

# Override .gitignore to check ALL files (rarely needed)
lsp-check . --no-ignore
```

**When to use --no-ignore:**

- Debugging issues in ignored files (e.g., generated code)
- Checking vendored dependencies
- Rare cases where you need complete repository analysis

**Note:** Even with --no-ignore, `.git/` directory is always excluded.

### Timing Control

```bash
# Longer timeout for large projects
lsp-check src/ --timeout 60

# Longer minimum wait for slow LSPs
lsp-check src/ --wait 5

# Longer quiet window for chatty LSPs
lsp-check src/ --quiet-ms 3000
```

**Timing strategy:**

1. **--wait** (default 1s): Minimum settle time before monitoring starts
2. **--quiet-ms** (default 1000ms): How long with no updates before considering "done"
3. **--timeout** (default 30s): Hard cap on total time

### File Limits

```bash
# Raise file limit for large projects
lsp-check . --max-files 500
```

Default limit is 200 files to prevent performance issues.

### Verbose Mode

```bash
lsp-check . --verbose
```

Shows real-time progress:

- LSP startup status
- Diagnostic count changes
- Silent duration tracking

### JSON Output Location

```bash
# Custom JSON output path
lsp-check . --json-out build/diagnostics.json

# Disable stdout (only JSON)
lsp-check . --no-stdout
```

## How It Works

1. **File Collection**: Uses `fd` to find source files (fast!)
   - Supports: Python, Lua, JS/TS, Rust, Go, Java, C/C++, and many more
   - **Respects .gitignore by default** (use `--no-ignore` to override)
   - Always excludes: `.git/` directory

2. **Git Root Check**: Ensures all files are in same git repository
   - Prevents LSP confusion from multiple projects
   - Errors if multiple roots detected

3. **Headless Neovim**: Opens all files to trigger LSP servers
   - Uses your actual Neovim config
   - LSP servers analyze code naturally

4. **Smart Settling**: Monitors diagnostic updates
   - Waits for minimum time (--wait)
   - Then waits for quiet window (--quiet-ms with no updates)
   - Or times out (--timeout)

5. **Structured Output**: JSON + pretty formatting
   - JSON for programmatic use
   - Colored stdout for human reading

## Common Diagnostic Sources

Different LSPs will show as different sources:

- **Python**: `Pyright`, `basedpyright`, `Ruff`
- **TypeScript/JavaScript**: `typescript-language-server`, `eslint`
- **Lua**: `lua-language-server`
- **Rust**: `rust-analyzer`
- **Go**: `gopls`

Use `--source` to filter to specific LSP when multiple are running.

## Interpreting Results

### Summary Mode (default)

```text
LSP Diagnostic Report
Generated: 2025-01-16T12:00:00Z
Files:     42
Totals:    15  (Errors: 3, Warnings: 8, Info: 3, Hints: 1)

Top files with issues:
  src/main.py: 5
  src/utils.py: 3
  tests/test_main.py: 2
```

Shows overview with top problematic files.

### Detailed Mode (--detailed)

```text
src/main.py
────────────────────────────────────────
ERROR    [42, 5]  type-error (Pyright)
  Type 'str' is not assignable to type 'int'

WARN     [58, 10]  unused-variable (Ruff)
  Unused variable 'result'
```

Shows every diagnostic with full context.

## Use Cases

### Before Committing

```bash
# Check files you changed (recommended approach)
lsp-check src/mymodule/ tests/test_mymodule.py --min-severity ERROR
```

Only commit if exit code is 0 and no errors shown.

### After Refactoring

```bash
# Verify no new warnings in affected modules
lsp-check src/affected_module/ --detailed --min-severity WARN
```

Compare diagnostic counts before/after refactoring.

### During Development

```bash
# Quick check of current file
lsp-check src/main.py

# Check module you're working on
lsp-check src/mymodule/

# Check specific related files
lsp-check src/api/ src/models/
```

### CI/CD Integration

```bash
# Fail build on errors in source directories
lsp-check src/ --no-stdout --json-out diagnostics.json
if jq -e '.summary.errors > 0' diagnostics.json; then
  echo "Build failed: LSP errors detected"
  exit 1
fi

# Or check all files respecting .gitignore
lsp-check . --no-stdout --json-out diagnostics.json
```

## Tips

- **Target your changes**: Only check files/folders you're actively working on
- **Use --verbose for slow LSPs**: See what's happening during collection
- **Filter to focus**: Use --min-severity and --source to reduce noise
- **Check before push**: Run lsp-check on modified files before committing
- **Set up aliases**: `alias lsp-errors='lsp-check --min-severity ERROR'` (then use: `lsp-errors src/`)
- **CI integration**: Add lsp-check to your CI pipeline with targeted paths
- **Respects .gitignore**: By default excludes ignored files (use --no-ignore if needed)

## Limitations

- **Requires Neovim**: Uses your Neovim config and LSP setup
- **Single git root**: Can't check files across multiple repos in one run
- **LSP must be configured**: Your Neovim must have working LSP for the file types
- **File limit**: Default 200 files (configurable with --max-files)
