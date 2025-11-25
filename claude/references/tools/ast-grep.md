# ast-grep (sg) - Structural Code Search

`sg` (ast-grep) is a tool for structural code search using Abstract Syntax Tree
patterns. Unlike text-based search (ripgrep), it understands code structure and
syntax.

## Quick Reference

**Most common patterns:**

```bash
sg -p 'def $FUNC($$$):'                    # Find all function definitions (Python)
sg -p 'class $CLASS($BASE):'               # Find class with inheritance
sg -p 'function_name($$$)'                 # Find all calls to function_name
sg -p 'export const $NAME = $$$'           # Find all exports (JS)
```

**Related:**

- [Package search skill](../../skills/code/package-search/SKILL.md) - Using sg
  for package exploration
- [Official ast-grep docs](https://ast-grep.github.io/)

---

## When to Use ast-grep Over ripgrep

**Use `sg` (ast-grep) when:**

- Finding function/class definitions with specific signatures
- Searching for patterns with variable names you don't know
- Finding all usages of a specific API pattern
- Understanding complex nested structures

**Use `rg` (ripgrep) when:**

- Simple text search (faster)
- Searching strings, comments, or documentation
- You know the exact text you're looking for

## Pattern Syntax

### Wildcards

- `$VAR` - Matches single AST node (variable, expression, etc.)
- `$$$` - Matches zero or more AST nodes (multiple arguments, statements, etc.)
- `$$` - Matches any single statement/expression

### Examples by Language

#### Python

```bash
# Find all function definitions
sg -p 'def $FUNC($$$):'

# Find functions with specific return type hint
sg -p 'def $FUNC($$$) -> $TYPE:'

# Find class definitions with inheritance
sg -p 'class $CLASS($BASE):'

# Find try-except blocks
sg -p 'try: $$$'

# Find all function calls (any arguments)
sg -p 'function_name($$$)'

# Find list comprehensions
sg -p '[$EXPR for $VAR in $ITER]'

# Find all imports of specific module
sg -p 'from $MODULE import $$$'
```

#### JavaScript/TypeScript

```bash
# Find React components
sg -p 'function $NAME(): JSX.Element { $$$ }'

# Find all exports
sg -p 'export const $NAME = $$$'
sg -p 'export function $NAME($$$) { $$$ }'

# Find arrow functions
sg -p '($$$) => $$$'

# Find async functions
sg -p 'async function $NAME($$$) { $$$ }'

# Find class methods
sg -p 'class $CLASS { $METHOD($$$) { $$$ } }'
```

#### Lua

```bash
# Find Neovim plugin setup functions
sg -p 'M.setup = function($$$) $$$ end'

# Find function definitions
sg -p 'function M.$METHOD($$$) $$$ end'

# Find local function definitions
sg -p 'local function $NAME($$$) $$$ end'
```

#### Rust

```bash
# Find impl blocks
sg -p 'impl $TYPE { $$$ }'

# Find public functions
sg -p 'pub fn $NAME($$$) -> $RETURN { $$$ }'

# Find match expressions
sg -p 'match $EXPR { $$$ }'
```

## Common Use Cases

### Understanding Package APIs

**Find all public functions in Python package:**

```bash
cd /path/to/package
sg -p 'def $FUNC($$$):' --json | jq '.[] | select(.text | test("^def [^_]"))'
```

**Find all exports in JavaScript package:**

```bash
sg -p 'export function $NAME($$$) { $$$ }' /path/to/package
sg -p 'export const $NAME = $$$' /path/to/package
```

### Finding API Usage Patterns

**Find all calls to specific function:**

```bash
sg -p 'api_function($$$)' src/
```

**Find all class instantiations:**

```bash
# Python
sg -p 'ClassName($$$)' src/

# JavaScript
sg -p 'new ClassName($$$)' src/
```

### Refactoring Assistance

**Find all functions with >3 parameters:**

```bash
# Python (requires manual filtering of results)
sg -p 'def $FUNC($P1, $P2, $P3, $P4, $$$):' src/
```

**Find all error handling patterns:**

```bash
# Python try-except
sg -p 'try: $$$ except $EXCEPT: $$$' src/

# JavaScript try-catch
sg -p 'try { $$$ } catch ($ERR) { $$$ }' src/
```

### Finding Implementation Patterns

**Find all implementations of interface/base class:**

```bash
# Python
sg -p 'class $CLASS(BaseClass):' src/

# TypeScript
sg -p 'class $CLASS implements $INTERFACE { $$$ }' src/
```

**Find callback patterns:**

```bash
# JavaScript callbacks
sg -p '$FUNC(function($$$) { $$$ })' src/

# JavaScript arrow function callbacks
sg -p '$FUNC(($$$) => $$$)' src/
```

## Advanced Usage

### Combining with Other Tools

```bash
# Find functions, count them
sg -p 'def $FUNC($$$):' src/ | wc -l

# Find functions, extract names
sg -p 'def $FUNC($$$):' --json | jq -r '.[].meta_variables.FUNC.text'

# Find and then read specific files
sg -p 'class $CLASS:' src/ --json | jq -r '.[].file' | xargs cat
```

### Multi-Pattern Search

```bash
# Find multiple export patterns
sg -p 'export const $NAME = $$$' src/
sg -p 'export function $NAME($$$) { $$$ }' src/
sg -p 'export default $$$' src/
```

### Language-Specific Search

```bash
# Search only Python files
sg -p 'def $FUNC($$$):' --lang python src/

# Search only TypeScript files
sg -p 'interface $NAME { $$$ }' --lang typescript src/
```

## JSON Output for Programmatic Use

```bash
# Get structured output
sg -p 'def $FUNC($$$):' --json src/ > functions.json

# Extract specific information
sg -p 'def $FUNC($$$):' --json src/ | jq -r '.[] | "\(.file):\(.line) - \(.meta_variables.FUNC.text)"'
```

## Tips

1. **Start simple**: Begin with basic patterns and refine
2. **Use JSON output**: For programmatic processing
3. **Test patterns**: Try on small directory first
4. **Combine with ripgrep**: Use rg for simple text, sg for structure
5. **Language awareness**: sg understands language-specific syntax

## Limitations

- Slower than ripgrep for simple text search
- Pattern syntax varies slightly by language
- Requires understanding of AST concepts
- Not all languages equally supported

## Common Patterns Library

### Python

- Functions: `def $FUNC($$$):`
- Classes: `class $CLASS($$$):`
- Imports: `from $MOD import $$$`
- Decorators: `@$DECORATOR`

### JavaScript/TypeScript

- Functions: `function $NAME($$$) { $$$ }`
- Arrow functions: `($$$) => $$$`
- Exports: `export $$$`
- Imports: `import $$$`

### Lua

- Functions: `function $NAME($$$) $$$ end`
- Local functions: `local function $NAME($$$) $$$ end`
- Tables: `$TABLE = { $$$ }`
