---
name: python
description: Python language-specific development rules, testing patterns, and tooling preferences. Use when working with Python code, scripts, or projects.
---

# Python Development Skill

Use this skill when working with Python code, libraries, or projects.

## Core Principles

- **Environment Management**: Always use `uv` for dependencies and virtual environments
- **Type Hints**: Use type hints for function signatures and complex data structures
  - **Use version-appropriate syntax**: Use native types (`list`, `dict`, `tuple`) instead of `typing.List`, `typing.Dict`, etc. for Python 3.9+
  - **Use built-in generics**: For Python 3.12+, use built-in generic syntax (`def foo[T](x: T) -> T`) instead of TypeVars
  - **Do NOT prioritize backward compatibility** unless the project's CLAUDE.md explicitly requires it
- **Testing**: Prefer `pytest` for testing with clear, descriptive test names
- **Linting**: Code should pass `ruff` checks (or equivalent configured linter)
- **Code Style**: Follow PEP 8, prefer comprehensions over loops when readable

## Python-Specific Style Guide

- **Minimal comments**: Self-documenting code with clear variable/function names (see [style guide](../../../references/style.md))
- **Simplicity over cleverness**: Readable Python > clever one-liners
- **Match existing patterns**: Follow the project's existing structure and conventions

### Type Hint Examples by Python Version

**Python 3.9+ (use built-in types):**
```python
def process_data(items: list[dict[str, Any]]) -> dict[str, int]:
    """Process items into a summary."""
    return {"total": len(items)}
```

**Python 3.12+ (use built-in generics):**
```python
# Old way (don't use):
# from typing import TypeVar
# T = TypeVar('T')
# def first[T](items: list[T]) -> T | None:

# New way (use this):
def first[T](items: list[T]) -> T | None:
    """Return first item or None."""
    return items[0] if items else None
```

## Testing with pytest

Python testing uses `pytest` as the preferred framework.

### Test Structure

```python
def test_should_return_sum_of_two_numbers():
    # Arrange
    calculator = Calculator()

    # Act
    result = calculator.add(2, 3)

    # Assert
    assert result == 5

def test_should_handle_negative_and_edge_cases():
    calculator = Calculator()

    # Multiple assertions testing the same concept (math correctness)
    assert calculator.add(-5, 3) == -2
    assert calculator.add(0, 0) == 0
    assert calculator.add(-1, -1) == -2
```

### Fixtures for Setup

```python
import pytest

@pytest.fixture
def calculator():
    """Provide a fresh Calculator instance for each test."""
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
```

### Best Practices

- Use descriptive test names: `test_should_return_empty_list_when_no_items_match()`
- Organize tests with clear arrange/act/assert structure
- Use fixtures for common setup
- Test one concept per test (multiple assertions are fine if testing same concept)
- See [TDD skill](../../code/tdd/SKILL.md) for test-driven development workflow

## Scripts in Skills

When creating Python scripts within skills, use `uv` to manage dependencies:

### Creating a Script with Dependencies

```bash
# Create a script file
cat > scripts/example.py << 'EOF'
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

def main():
    print("Hello, world!")

if __name__ == "__main__":
    main()
EOF

# Make it executable
chmod +x scripts/example.py

# Add dependencies using uv
uv add --script scripts/example.py pandas numpy

# Run the script
uv run scripts/example.py
```

### Script Dependency Block Format

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pandas>=2.0.0",
#     "numpy",
#     "requests",
# ]
# ///
```

- **Specify Python version**: Use `requires-python` to set minimum Python version
- **Add dependencies**: Use `uv add --script script.py package` to add dependencies
- **Version constraints**: Can specify version ranges like `pandas>=2.0.0`
- **Run with**: `uv run scripts/script.py` - uv creates isolated environment automatically

## Project Environment

When working in a project with a Python virtual environment:
- Activate the project's virtualenv
- Use project dependencies, not script-level ones
- Check for `pyproject.toml`, `requirements.txt`, or `uv.lock`
- Verify Python version: `python --version`

## Further Reading

- [Detailed Style Guide](../../../references/style.md)
- [Testing Patterns](../../../references/testing.md)
- [Development Workflow](../../../references/development.md)
