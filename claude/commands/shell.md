---
description:
  Shell scripting patterns for bash/zsh with macOS and Linux portability
---

# Task

Write robust, portable shell scripts that work across macOS and Linux
(Ubuntu/Debian).

## Core Principles

- **Portability First**: Code must work on both macOS and Linux
- **Bash 3.2.57**: macOS default - limited features, no associative arrays
- **Zsh 5.9**: Primary shell - feature-rich, preferred when available
- **Detailed Comments**: Unlike other code, leave detailed comments in shell
  scripts
  - Shell edge cases are subtle and configs are frequently modified

## Workflow

### 1. Start with Error Handling

Every script should start with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# -e: Exit on error
# -u: Exit on undefined variable
# -o pipefail: Exit if any command in pipeline fails
```

**For zsh:**

```zsh
#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
```

### 2. Always Quote Variables

```bash
# Good - quoted
if [[ -f "$file" ]]; then
    echo "Processing $file"
    process_file "$file"
fi

# Bad - unquoted (will break on spaces)
if [[ -f $file ]]; then
    echo "Processing $file"
    process_file $file
fi
```

**Quote everything:**

- `"$var"`
- `"${array[@]}"`
- Command substitutions: `"$(command)"`

### 3. Handle Platform Differences

```bash
# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS specific
    sed -i '' 's/old/new/' file.txt
else
    # Linux
    sed -i 's/old/new/' file.txt
fi

# Or use portable alternatives
# Instead of sed -i, use a temp file:
sed 's/old/new/' file.txt > file.tmp && mv file.tmp file.txt
```

**Common differences:**

- `sed -i` syntax (macOS needs `''`)
- `date` command options
- `readlink` (use `realpath` on Linux, `greadlink` on macOS)
- `stat` command format

### 4. Use Bash 3.2 Compatible Features

**Available in Bash 3.2:**

- Arrays: `arr=(a b c)`
- `[[ ]]` conditionals
- `$()` command substitution
- String manipulation: `${var#pattern}`, `${var%pattern}`

**NOT available in Bash 3.2:**

- Associative arrays: `declare -A` (use bash 4+ or zsh)
- `readarray` / `mapfile`
- `&>>` redirect operator

### 5. Handle Paths and Filenames Safely

```bash
# Get script directory (portable)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Handle paths with spaces
config_dir="$HOME/.config/my app"
mkdir -p "$config_dir"
ls -la "$config_dir"

# Iterate over files safely
find . -type f -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    echo "Processing: $file"
done
```

### 6. Check Dependencies

```bash
# Check if command exists
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Check if file exists
if [[ ! -f "$config_file" ]]; then
    echo "Error: Config file not found: $config_file" >&2
    exit 1
fi
```

### 7. Use Functions for Reusability

```bash
# Function with error handling and comments
process_package() {
    local package="$1"

    # Check if package is already installed
    if command -v "$package" &> /dev/null; then
        echo "✓ $package already installed"
        return 0
    fi

    # Install based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install "$package"
    else
        sudo apt-get install -y "$package"
    fi
}

# Use it
process_package "git"
process_package "curl"
```

### 8. Debugging

```bash
# Enable debug mode
set -x  # Print commands as they execute

# Disable debug mode
set +x

# Or run script with debugging
bash -x script.sh
```

## Common Patterns

### Loop Over Files

```bash
# Safe iteration (handles spaces and special chars)
find . -type f -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    echo "File: $file"
done

# Simple case (no special chars)
for file in *.txt; do
    [[ -e "$file" ]] || continue  # Skip if no matches
    echo "File: $file"
done
```

### Read File Line by Line

```bash
while IFS= read -r line; do
    echo "Line: $line"
done < "$file"
```

### String Manipulation

```bash
# Remove prefix
file="path/to/file.txt"
echo "${file#*/}"      # to/file.txt
echo "${file##*/}"     # file.txt

# Remove suffix
echo "${file%.*}"      # path/to/file
echo "${file%%/*}"     # path

# Replace
echo "${file/to/from}" # path/from/file.txt
```

### Conditional Checks

```bash
# File tests
[[ -f "$file" ]]       # File exists
[[ -d "$dir" ]]        # Directory exists
[[ -x "$file" ]]       # File is executable
[[ -s "$file" ]]       # File exists and not empty

# String tests
[[ -z "$var" ]]        # String is empty
[[ -n "$var" ]]        # String is not empty
[[ "$a" == "$b" ]]     # Strings equal

# Numeric tests
[[ "$a" -eq "$b" ]]    # Equal
[[ "$a" -lt "$b" ]]    # Less than
[[ "$a" -gt "$b" ]]    # Greater than
```

## Testing Scripts

```bash
# Dry run mode
if [[ "${DRY_RUN:-}" == "true" ]]; then
    echo "Would execute: $command"
else
    eval "$command"
fi

# Usage
DRY_RUN=true ./script.sh
```

## Related Documentation

- [Style Guide](~/.claude/references/style.md) - General code style
- [Development Workflow](~/.claude/references/development.md) - Development
  process

For shell-specific issues, check `man bash` or `man zsh`.
