---
name: shell
description: Shell scripting patterns for bash/zsh. Use when writing shell scripts, debugging script errors, ensuring portability across macOS and Linux, or handling edge cases in shell scripting.
---

## Quick Reference

**Error handling:**

```bash
set -euo pipefail  # Exit on error, unset vars, pipe failures
```

**Quoting:**

```bash
"$var"      # Always quote variables
"${array[@]}"  # Quote array expansions
```

**Portability checks:**

- Test on both macOS and Linux (this repo supports both)
- Use `[[ ]]` for conditionals (bash/zsh), not `[ ]`
- Check command availability: `command -v tool >/dev/null`

**Related:**

- [Development workflow](../../../references/development.md) - Script testing
- [Style guide](../../../references/style.md) - General principles

---

## Error Handling

### Strict Mode

Always start scripts with strict mode:

```bash
#!/usr/bin/env bash
set -euo pipefail

# -e: Exit on error
# -u: Error on unset variables
# -o pipefail: Pipe fails if any command fails
```

### Trap for Cleanup

```bash
#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  # Cleanup code here
  rm -f /tmp/tempfile.$$
}

trap cleanup EXIT  # Run cleanup on script exit
```

### Check Command Existence

```bash
# Check if command exists before using
if ! command -v fd >/dev/null; then
  echo "Error: fd not found" >&2
  exit 1
fi
```

---

## Quoting and Escaping

### Always Quote Variables

```bash
# Bad - word splitting, glob expansion
cp $file $dest

# Good - prevents issues
cp "$file" "$dest"

# Bad - array without quotes
for item in ${array[@]}; do
  echo $item
done

# Good - proper quoting
for item in "${array[@]}"; do
  echo "$item"
done
```

### When NOT to Quote

```bash
# Intentional word splitting
options="-la -h"
ls $options  # Want word splitting here

# But better to use array
options=(-la -h)
ls "${options[@]}"
```

---

## Portability (macOS vs Linux)

This repository supports both macOS and Linux. Write portable scripts:

### Use Portable Commands

```bash
# Bad - GNU-specific
sed -i 's/old/new/' file  # Linux
sed -i '' 's/old/new/' file  # macOS

# Good - portable
sed 's/old/new/' file > file.tmp && mv file.tmp file

# Or detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/old/new/' file
else
  sed -i 's/old/new/' file
fi
```

### Check Tool Availability

```bash
# Use fd if available, fall back to find
if command -v fd >/dev/null; then
  fd -t f "*.sh"
else
  find . -type f -name "*.sh"
fi
```

### Shebang for Portability

```bash
#!/usr/bin/env bash  # Good - finds bash in PATH
#!/bin/bash          # Bad - assumes location
```

---

## Conditionals

### Use `[[ ]]` for bash/zsh

```bash
# Good - bash/zsh test
if [[ -f "$file" ]]; then
  echo "File exists"
fi

# Good - multiple conditions
if [[ -f "$file" && -r "$file" ]]; then
  cat "$file"
fi

# Good - pattern matching
if [[ "$var" == *.txt ]]; then
  echo "Text file"
fi

# Good - regex matching
if [[ "$var" =~ ^[0-9]+$ ]]; then
  echo "Number"
fi
```

### Common Tests

```bash
[[ -f "$file" ]]      # File exists
[[ -d "$dir" ]]       # Directory exists
[[ -x "$cmd" ]]       # Executable
[[ -z "$var" ]]       # Variable is empty
[[ -n "$var" ]]       # Variable is not empty
[[ "$a" == "$b" ]]    # String equality
[[ "$a" != "$b" ]]    # String inequality
```

---

## Functions

```bash
# Define functions
do_something() {
  local input="$1"  # Use local for function variables
  local result

  result="$(process "$input")"
  echo "$result"
}

# Call functions
output="$(do_something "arg")"
```

---

## Arrays

```bash
# Define array
files=("file1.txt" "file2.txt" "file3.txt")

# Iterate
for file in "${files[@]}"; do
  echo "$file"
done

# Array length
echo "Count: ${#files[@]}"

# Add to array
files+=("file4.txt")
```

---

## Common Pitfalls

### Word Splitting

```bash
# Bad - will break on spaces
for file in $(ls *.txt); do
  echo $file
done

# Good - proper quoting
for file in *.txt; do
  echo "$file"
done

# Or with array
files=(*.txt)
for file in "${files[@]}"; do
  echo "$file"
done
```

### Unquoted Variables

```bash
# Bad - breaks with spaces or special chars
if [ -f $file ]; then
  rm $file
fi

# Good - always quote
if [[ -f "$file" ]]; then
  rm "$file"
fi
```

### Command Substitution

```bash
# Good - use $()
result="$(command arg)"

# Avoid - backticks harder to nest
result=`command arg`
```

---

## Testing Shell Scripts

```bash
# Test script syntax
bash -n script.sh

# Run with tracing
bash -x script.sh

# Test on both platforms
# macOS: run locally
# Linux: use Docker or VM
```

### Manual Testing

```bash
# Create test directory
mkdir -p /tmp/test-script
cd /tmp/test-script

# Create test files
touch "file with spaces.txt"
touch "normal.txt"

# Run script with test data
./script.sh *.txt
```

---

## Comments in Shell Scripts

Unlike other languages, shell scripts benefit from more detailed comments:

```bash
# Check if running as root
# Required for system-wide installation
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Create backup before modifying
# Allows rollback if something goes wrong
cp "$config" "$config.bak"
```

**Why more comments:** Shell syntax is terse and can be cryptic. Comments explain intent and gotchas.

---

## Related Resources

- [Style guide](../../../references/style.md) - General code principles
- [Development workflow](../../../references/development.md) - Testing and debugging
- [Bash manual](https://www.gnu.org/software/bash/manual/) - Comprehensive reference
- `man bash` - Local bash manual
