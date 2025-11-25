---
description:
  Python standards and best practices that are not specified in the general
  style guide.
---

# Task

Write Python code following modern practices with proper type hints and tooling.

## Core Principles

- **Environment Management**: Use `uv` for dependencies and virtual environments
  (unless project uses `poetry`)
- **Type Hints**: Use type hints for function signatures and complex data
  structures
- **Modern Python**: Use native types (`list`, `dict`) over `typing.List`
  (Python 3.9+)
- **Code Style**: Follow PEP 8, prefer comprehensions when readable
- **Minimal docstrings**: Only write docstrings when truly necessary (see
  criteria below)

## Project Setup

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

## Type Hints

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

## When to Write Docstrings

<IMPORTANT>Only write docstrings if one of these is true:</IMPORTANT>

1. **Function name/signature insufficient**: The name and signature can't convey
   enough detail
   - First check if improving the name/signature would help
2. **Public API**: Class, function, or module used by others needs comprehensive
   documentation
3. **Critical/unintuitive behavior**: Something non-obvious that needs
   explanation

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

## Related Documentation

- [uv tool guide](~/.claude/references/tools/uv.md) - Complete uv documentation
- [Testing Guide](~/.claude/references/testing.md) - Testing patterns
- [Style Guide](~/.claude/references/style.md) - General code style
- `/tdd` - Test-driven development workflow
- `/clean` - Refactoring workflow
