---
description: Python development with uv, type hints, and modern Python practices
---

# Task

Write Python code following modern practices with proper type hints and tooling.

## Core Principles

- **Environment Management**: Use `uv` for dependencies and virtual environments (unless project uses `poetry`)
- **Type Hints**: Use type hints for function signatures and complex data structures
- **Modern Python**: Use native types (`list`, `dict`) over `typing.List` (Python 3.9+)
- **Code Style**: Follow PEP 8, prefer comprehensions when readable
- **Minimal docstrings**: Only write docstrings when truly necessary (see criteria below)

## Workflow

### 1. Project Setup

Check project structure first:

```bash
# Look for project configuration
ls pyproject.toml requirements.txt uv.lock poetry.lock

# Check Python version
python --version

# Verify virtual environment
ls .venv/
```

**Using uv:**

```bash
# Create virtual environment
uv venv

# Install dependencies
uv pip install -r requirements.txt

# Add new dependency
uv add package-name

# Run commands in environment
uv run python script.py
uv run pytest
```

**Using poetry (if project configured):**

```bash
poetry install
poetry add package-name
poetry run python script.py
poetry run pytest
```

### 2. Type Hints

Use type hints for clarity:

```python
# Python 3.9+ - use native types
def process_items(items: list[str]) -> dict[str, int]:
    return {item: len(item) for item in items}

# Python 3.12+ - generic syntax
def first[T](items: list[T]) -> T | None:
    return items[0] if items else None

# Complex types
from collections.abc import Callable

def apply(func: Callable[[int], int], value: int) -> int:
    return func(value)
```

**Don't prioritize backward compatibility** unless CLAUDE.md requires it.

### 3. When to Write Docstrings

<IMPORTANT>Only write docstrings if one of these is true:</IMPORTANT>

1. **Function name/signature insufficient**: The name and signature can't convey enough detail
   - First check if improving the name/signature would help
2. **Public API**: Class, function, or module used by others needs comprehensive documentation
3. **Critical/unintuitive behavior**: Something non-obvious that needs explanation

**Examples where docstrings are NOT needed:**

```python
# Good - self-documenting
def calculate_total_price(items: list[Item], tax_rate: float) -> float:
    subtotal = sum(item.price for item in items)
    return subtotal * (1 + tax_rate)

# Good - clear from signature
def find_user_by_email(email: str) -> User | None:
    return db.query(User).filter_by(email=email).first()
```

**Examples where docstrings ARE needed:**

```python
# Complex algorithm - needs explanation
def dijkstra(graph: Graph, start: Node, end: Node) -> list[Node]:
    """Find shortest path using Dijkstra's algorithm.

    Uses a priority queue to efficiently explore paths.
    Returns empty list if no path exists.
    """
    ...

# Public API - external users need docs
class DataProcessor:
    """Process and transform data from various sources.

    Supports CSV, JSON, and XML formats with automatic type detection.
    Thread-safe for concurrent processing.
    """
    ...
```

### 4. Code Style

**Comprehensions for simple transformations:**

```python
# Good - readable comprehension
squared = [x**2 for x in numbers]
evens = [x for x in numbers if x % 2 == 0]
lookup = {user.id: user for user in users}

# Bad - too complex
result = [
    transform(process(x))
    for x in items
    if validate(x) and check(x)
    for y in x.related
    if y.active
]

# Better - use explicit loop
result = []
for x in items:
    if not (validate(x) and check(x)):
        continue
    for y in x.related:
        if y.active:
            result.append(transform(process(x)))
```

**Match existing patterns:**

```python
# Check project conventions first
rg "class.*:" --type py | head -5
rg "def.*:" --type py | head -5

# Follow what you find
```

### 5. Error Handling

```python
# Specific exceptions
try:
    data = load_config(path)
except FileNotFoundError:
    logger.error(f"Config not found: {path}")
    return default_config()
except json.JSONDecodeError as e:
    logger.error(f"Invalid JSON in {path}: {e}")
    raise

# Early returns (guard clauses)
def process_order(order: Order | None) -> PaymentResult:
    if order is None:
        raise ValueError("Order cannot be None")
    if not order.is_valid():
        raise ValueError("Invalid order")
    if not order.items:
        return PaymentResult.empty()

    # Main logic at lowest indentation
    return calculate_payment(order)
```

### 6. Testing

```bash
# Run tests
uv run pytest

# With coverage
uv run pytest --cov

# Specific test
uv run pytest tests/test_module.py::test_function

# Watch mode (if available)
uv run pytest-watch
```

For TDD workflow, use `/tdd` command.

### 7. Common Patterns

**Context managers:**

```python
from contextlib import contextmanager

@contextmanager
def database_transaction():
    conn = connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
```

**Dataclasses:**

```python
from dataclasses import dataclass

@dataclass
class User:
    id: int
    name: str
    email: str
    is_active: bool = True
```

**Enums:**

```python
from enum import Enum

class Status(Enum):
    PENDING = "pending"
    ACTIVE = "active"
    COMPLETE = "complete"
```

## Debugging

```python
# Breakpoint (Python 3.7+)
breakpoint()

# Or use pdb
import pdb; pdb.set_trace()

# Rich for better output
from rich import print
print(complex_object)
```

## Related Documentation

- [uv tool guide](~/.claude/references/tools/uv.md) - Complete uv documentation
- [Testing Guide](~/.claude/references/testing.md) - Testing patterns
- [Style Guide](~/.claude/references/style.md) - General code style
- `/tdd` - Test-driven development workflow
- `/clean` - Refactoring workflow
