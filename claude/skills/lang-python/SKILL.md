---
name: python
description: Python language-specific development rules, testing patterns, and tooling preferences. Use when writing Python code, setting up Python environments, choosing between type hint syntaxes, configuring pytest tests, or managing dependencies with uv.
---

## Quick Reference

**Type hints (Python 3.9+):**

```python
def process(items: list[dict[str, Any]]) -> dict[str, int]:
    return {"total": len(items)}
```

**pytest structure:**

```python
def test_should_return_sum():
    # Arrange
    calc = Calculator()
    # Act
    result = calc.add(2, 3)
    # Assert
    assert result == 5
```

**Environment:**

- Use `uv` for dependencies and virtual environments
- `uvx <tool>` to run tools without installing

**Related:**

- [uv tool guide](../../../references/tools/uv.md) - Complete uv documentation
- [Testing patterns](../../../references/testing.md) - General testing guidance
- [Style guide](../../../references/style.md) - Code style principles

---

## Core Principles

- **Environment Management**: Always use `uv` for dependencies and virtual environments
- **Type Hints**: Use type hints for function signatures and complex data structures
  - **Python 3.9+**: Use native types (`list`, `dict`, `tuple`) not `typing.List`
  - **Python 3.12+**: Use built-in generics (`def foo[T](x: T) -> T`)
  - **Don't prioritize backward compatibility** unless project CLAUDE.md requires it
- **Testing**: Prefer `pytest` for testing with clear, descriptive test names
- **Linting**: Code should pass `ruff` checks (or configured linter)
- **Code Style**: Follow PEP 8, prefer comprehensions when readable

---

## Type Hint Patterns

### Python 3.9+ (Built-in Types)

```python
# Use native types, not typing.List/Dict
def process_data(items: list[dict[str, Any]]) -> dict[str, int]:
    """Process items into a summary."""
    return {"total": len(items)}

# Union types
def get_user(id: int) -> User | None:
    return db.query(id)

# Optional is just sugar for | None
def find(name: str, default: str | None = None) -> str:
    return name or default or "unknown"
```

### Python 3.12+ (Built-in Generics)

```python
# New generic syntax (no TypeVar needed)
def first[T](items: list[T]) -> T | None:
    """Return first item or None."""
    return items[0] if items else None

# Multiple type parameters
def zip_dict[K, V](keys: list[K], values: list[V]) -> dict[K, V]:
    return dict(zip(keys, values))
```

---

## Testing with pytest

### Test Structure (AAA Pattern)

```python
def test_should_calculate_total_correctly():
    # Arrange
    calculator = Calculator()

    # Act
    result = calculator.add(2, 3)

    # Assert
    assert result == 5

def test_should_handle_negative_numbers():
    calculator = Calculator()

    # Multiple assertions testing same concept (math correctness)
    assert calculator.add(-5, 3) == -2
    assert calculator.add(0, 0) == 0
    assert calculator.add(-1, -1) == -2
```

### Fixtures for Setup

```python
import pytest

@pytest.fixture
def calculator():
    """Provide fresh Calculator instance for each test."""
    return Calculator()

def test_should_handle_division_by_zero(calculator):
    with pytest.raises(ZeroDivisionError):
        calculator.divide(10, 0)
```

### Running Tests

```bash
# Run all tests
pytest

# Run specific file
pytest tests/test_calculator.py

# Run with coverage
pytest --cov=mymodule tests/

# Run verbose
pytest -v

# Run in parallel (requires pytest-xdist)
pytest -n auto
```

### Best Practices

- **Descriptive names**: `test_should_return_empty_list_when_no_items_match()`
- **AAA structure**: Arrange, Act, Assert - clear separation
- **Use fixtures**: For common setup/teardown
- **One concept per test**: Multiple assertions OK if testing same concept
- See [TDD skill](../code-tdd/SKILL.md) for test-driven workflow

[Complete testing patterns →](../../../references/testing.md)

---

## Environment Management with uv

### Virtual Environments

```bash
# Create venv
uv venv

# Sync dependencies from pyproject.toml
uv sync

# Add dependency
uv add requests

# Add dev dependency
uv add --dev pytest
```

### Running Tools Without Installation

```bash
# Run tool without installing (uvx)
uvx ruff check .
uvx black .
uvx mypy src/
```

### Inline Script Dependencies

For standalone scripts with dependencies:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "requests",
#     "pandas>=2.0.0",
# ]
# ///

import requests
import pandas as pd

# Your script here
```

[Complete uv guide →](../../../references/tools/uv.md)

---

## Python-Specific Style

- **Minimal comments**: Self-documenting code with clear names (see [style guide](../../../references/style.md))
- **Simplicity over cleverness**: Readable Python > clever one-liners
- **Match existing patterns**: Follow project structure and conventions
- **Comprehensions when readable**: List/dict comprehensions for simple transformations

```python
# Good - clear comprehension
active_users = [user for user in users if user.is_active]

# Good - explicit loop for complex logic
results = []
for item in items:
    processed = complex_transformation(item)
    if processed.is_valid():
        results.append(enrich_data(processed))
```

---

## Project Environment

When working in a project with Python virtual environment:

1. Check for `pyproject.toml`, `requirements.txt`, or `uv.lock`
2. Activate virtualenv or use `uv run`
3. Verify Python version: `python --version`
4. Use project dependencies, not script-level ones

```bash
# Check Python version
python --version

# Activate venv (if needed)
source .venv/bin/activate

# Or use uv run
uv run python script.py
uv run pytest
```

---

## Related Resources

- [uv tool guide](../../../references/tools/uv.md) - Environment and dependency management
- [Style guide](../../../references/style.md) - General code style
- [Testing patterns](../../../references/testing.md) - Comprehensive testing guidance
- [TDD workflow](../code-tdd/SKILL.md) - Test-driven development
- [Development workflow](../../../references/development.md) - Development process
