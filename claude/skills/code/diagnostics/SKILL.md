---
name: diagnostics
description: LSP diagnostics extraction and analysis using lsp-check tool. Use when investigating errors, warnings, or code issues, before commits, or after refactoring to verify code health.
---

# Diagnostics Skill

Use this skill when investigating errors, warnings, or code issues reported by language servers (LSP), or when verifying code health before commits or after refactoring.

## Purpose

The `lsp-check` tool provides automated LSP diagnostic collection by:
- Opening files in headless Neovim to trigger LSP servers
- Collecting diagnostics with smart settling (waits for diagnostic updates to stabilize)
- Outputting structured JSON + pretty-formatted results
- Supporting filtering by severity and LSP source

## Basic Usage

### Check Current Directory

```bash
lsp-check .
```

Output shows summary with top files containing issues.

### Detailed Diagnostics

```bash
lsp-check . --detailed
```

Shows all diagnostics file-by-file with:
- Color-coded severity (ERROR=red, WARN=yellow, INFO=blue, HINT=gray)
- Line and column numbers
- Diagnostic codes and sources
- Full diagnostic messages

### Filter by Severity

```bash
# Only errors
lsp-check . --detailed --min-severity ERROR

# Warnings and errors (excludes info/hints)
lsp-check . --detailed --min-severity WARN
```

Severity levels (most to least severe): `ERROR` > `WARN` > `INFO` > `HINT`

### Filter by LSP Source

```bash
# Only pyright diagnostics
lsp-check . --detailed --source pyright

# Only typescript diagnostics
lsp-check . --detailed --source typescript-language-server
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

### Timing Control

```bash
# Longer timeout for large projects
lsp-check . --timeout 60

# Longer minimum wait for slow LSPs
lsp-check . --wait 5

# Longer quiet window for chatty LSPs
lsp-check . --quiet-ms 3000
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
   - Excludes: `.git/`, `node_modules/`, `__pycache__/`

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

## Integration with Development Workflow

### Before Committing

```bash
# Check for any errors before committing
lsp-check . --min-severity ERROR
```

Only commit if exit code is 0 and no errors shown.

### After Refactoring

```bash
# Verify no new warnings introduced
lsp-check . --detailed --min-severity WARN
```

Compare diagnostic counts before/after refactoring.

### During Development

```bash
# Quick check of current file
lsp-check main.py

# Check module
lsp-check src/mymodule/
```

### CI/CD Integration

```bash
# Fail build on errors
lsp-check . --no-stdout --json-out diagnostics.json
if jq -e '.summary.errors > 0' diagnostics.json; then
  echo "Build failed: LSP errors detected"
  exit 1
fi
```

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

```
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

```
src/main.py
────────────────────────────────────────
ERROR    [42, 5]  type-error (Pyright)
  Type 'str' is not assignable to type 'int'

WARN     [58, 10]  unused-variable (Ruff)
  Unused variable 'result'
```

Shows every diagnostic with full context.

## Diagnostic Workflow

1. **Run diagnostics**: `lsp-check . --detailed`
2. **Prioritize errors**: Fix ERROR severity first
3. **Address warnings**: Then WARN severity
4. **Consider info/hints**: HINT and INFO can often be ignored
5. **Re-run**: `lsp-check .` to verify fixes
6. **Commit**: When clean (or acceptable)

## Tips

- **Use --verbose for slow LSPs**: See what's happening
- **Filter to focus**: Use --min-severity and --source to reduce noise
- **Check before push**: Make it a habit to run lsp-check before committing
- **Set up aliases**: `alias lsp-errors='lsp-check . --min-severity ERROR'`
- **CI integration**: Add lsp-check to your CI pipeline

## Limitations

- **Requires Neovim**: Uses your Neovim config and LSP setup
- **Single git root**: Can't check files across multiple repos in one run
- **LSP must be configured**: Your Neovim must have working LSP for the file types
- **File limit**: Default 200 files (configurable with --max-files)

## Language-Specific Notes

For language-specific LSP setup and configuration:
- **Python**: See [python skill](../../language/python/SKILL.md)
- **Lua/Neovim**: See [neovim skill](../../language/neovim/SKILL.md)

## Further Reading

- [Development Workflow](../../../references/development.md)
- [Clean Code](../clean/SKILL.md) - for fixing diagnostic issues
- Script location: `~/generic/dotfiles/scripts/lsp-check`
