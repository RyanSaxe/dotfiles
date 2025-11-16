---
name: tdd
description: Test-Driven Development workflow for writing tests first before implementation. Use when implementing features where behavior should be defined by tests first, fixing bugs that need regression tests, or working with functional units that benefit from TDD approach.
---

# Test-Driven Development (TDD) Skill

Use this skill when implementing features where tests should drive the design, or when TDD is the appropriate approach for the problem at hand.

## Core Philosophy

**Goal**: Write the most concise and clear set of tests such that you are confident your code does what you want it to do.

**NOT the goal**: Writing 500 lines of test code to test 50 lines of real code. Extensive test suites should be rare exceptions, not the norm.

## TDD Cycle

Follow the Red-Green-Refactor cycle:

1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code while keeping tests green (use [clean code skill](../clean/SKILL.md) for guidance)

## When to Use TDD

✅ **TDD is ideal for:**
- Testing **functional units** (pure functions, algorithms, business logic)
- Implementing features with clear, well-defined requirements
- Fixing bugs (write test that reproduces bug first)
- Building APIs, libraries, or utility functions
- Complex logic that needs to be proven correct
- When the interface/contract is clear before implementation

⚠️ **TDD is NOT ideal for:**
- **End-to-end (e2e) tests** - these should be written after implementation unless explicitly requested
- **Integration tests** - usually written after components are working individually
- **UI/visual elements** - often need experimentation and visual verification
- **Exploratory prototyping** - when you're still figuring out what to build
- **Unclear requirements** - TDD requires knowing what "correct" looks like
- **External API integrations** - hard to test-drive without mocking extensively (see mocking section)
- **Performance optimization** - often needs profiling and experimentation first
- **Configuration/setup code** - usually better to test the behavior it enables
- **Glue code** - code that just connects components often doesn't need test-first approach

## Mocking: Avoid Unless Absolutely Necessary

**Strong stance**: Mocking should be fully avoided except in rare, specific cases.

### When Mocking IS Necessary

- **External paid APIs**: Don't want to incur costs during test runs
- **Slow operations**: Database queries, file I/O that would make tests too slow
- **Non-deterministic behavior**: Random number generation, current time, external data sources
- **Unavailable dependencies**: Third-party service that doesn't have a test environment
- **Hardware interactions**: Serial ports, GPIO pins, cameras, etc.

### When Mocking Is NOT Necessary (Use Real Objects Instead)

- **Internal modules**: Test with the real implementations
- **Pure functions**: No need to mock, they're deterministic
- **In-memory data structures**: Lists, dicts, objects - use the real thing
- **Simple utilities**: String formatters, calculators, validators - test the real code

**Why avoid mocks?**
- Mocks test your expectations, not actual behavior
- Mocks can drift from real implementations
- Over-mocking makes tests brittle and hard to maintain
- Real objects often aren't that expensive to use in tests

## Test Organization

- **Use descriptive test names**: `test_should_<expected_behavior>_when_<condition>()`
- **Follow AAA pattern**: Arrange, Act, Assert
- **Test one concept per test**: Multiple assertions are fine if they test the same concept
- **Use setup/teardown**: `before_each`, `after_each`, or fixtures for common setup

## Language-Specific Testing

For detailed testing patterns, examples, and best practices for specific languages:
- **Python**: See [python skill](../../language/python/SKILL.md) for pytest patterns
- **Lua/Neovim**: See [neovim skill](../../language/neovim/SKILL.md) for mini.test patterns
- **JavaScript/TypeScript**: Check project for vitest/jest setup

Each language skill contains testing examples and conventions specific to that ecosystem.

## Test Coverage Philosophy

- Focus on **confidence**, not coverage percentage
- **Test behavior**, not implementation details
- **Test edge cases** and error conditions for critical logic
- **Don't obsess** over 100% coverage
- More code doesn't mean better tests - conciseness and clarity matter

## TDD Workflow

### 1. Align on the Interface

Define the function signature, inputs, outputs, and expected behavior before writing any code or tests.

```python
# What we're building:
# Function: add(a: int, b: int) -> int
# Behavior: Returns sum of two integers
# Edge cases: Should handle negative numbers, zeros
```

### 2. Write the Test First (Red)

```python
def test_should_return_sum_of_two_numbers():
    calculator = Calculator()
    result = calculator.add(2, 3)
    assert result == 5
```

### 3. Run the Test (Should Fail)

```bash
pytest test_calculator.py
# FAILED - Calculator not implemented
```

### 4. Write Minimal Implementation (Green)

```python
class Calculator:
    def add(self, a, b):
        return a + b
```

### 5. Run the Test (Should Pass)

```bash
pytest test_calculator.py
# PASSED
```

### 6. Refactor (If Needed)

Improve code quality while keeping tests green. Reference the [clean code skill](../clean/SKILL.md) for refactoring guidance.

### 7. Repeat

Add more tests for edge cases, then implement. Keep the cycle tight and fast.

## Further Reading

- [Detailed Testing Guide](../../../references/testing.md)
- [Clean Code Principles](../clean/SKILL.md) - for refactoring step
- [Development Workflow](../../../references/development.md)
- [Python Testing](../../language/python/SKILL.md)
- [Neovim Testing](../../language/neovim/SKILL.md)
