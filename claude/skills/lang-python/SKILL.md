---
name: python
description: Python language-specific development rules and patterns. Use when writing python code.
---

## Quick Reference

- [uv tool guide](../../../references/tools/uv.md) - Complete uv documentation
- [Testing patterns](../../../references/testing.md) - General testing guidance
- [Style guide](../../../references/style.md) - Code style principles

---

## Core Principles

- **Environment Management**: Use `uv` for dependencies and virtual environments unless the project is configured to use `poetry`. For both of them, the `run` command should drive your execution.
- **Type Hints**: Use type hints for function signatures and complex data structures
  - **Python 3.9+**: Use native types (`list`, `dict`, `tuple`) not `typing.List`
  - **Python 3.12+**: Use built-in generics (`def foo[T](x: T) -> T`)
  - **Don't prioritize backward compatibility** unless project CLAUDE.md requires it
- **Code Style**: Follow PEP 8, prefer comprehensions when readable

---

## Python-Specific Style

- **Minimal comments**: Self-documenting code with clear names (see [style guide](../../references/style.md)).
- **Simplicity over cleverness**: Readable Python > clever one-liners
- **Match existing patterns**: Follow project structure and conventions
- **Comprehensions when readable**: List/dict comprehensions for simple transformations

<IMPORTANT>Do not write docstrings unless one of the following is true</IMPORTANT>

1. The function name and signature could never possibly provide enough detail to know what is going on. Note that sometimes the function name and signature is insufficient, but that itself could be improved
2. The class, function, or module is a public api that will be used by others and needs comprehensive documentation
3. There is something critical or unintuitive that needs to be explained

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
