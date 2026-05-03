---
description: Test-Driven Development workflow - write tests first, implement second
---

# Task

Follow the Test-Driven Development (TDD) cycle to build features with confidence through test-first development.

## Core Philosophy

**Goal:** Write the most concise and clear set of tests such that you are confident your code does what you want it to do.

**NOT the goal:** Writing 500 lines of test code to test 50 lines of real code.

## TDD Cycle: Red-Green-Refactor

1. **🔴 Red** - Write a failing test that defines desired behavior
2. **🟢 Green** - Write minimal code to make the test pass
3. **🔵 Refactor** - Improve code while keeping tests green (use `/clean`)

Keep the cycle tight and fast - **minutes, not hours**.

## Workflow

### 1. Align on Interface

Before writing any code, clarify:

- Function signature and types
- Expected behavior
- Edge cases to handle
- Success and failure scenarios

**Example:**

```python
# What we're building:
# Function: add(a: int, b: int) -> int
# Behavior: Returns sum of two integers
# Edge cases: Handle negatives, zeros
```

### 2. Write Test First (Red)

Write a test that describes the behavior you want:

```python
def test_should_return_sum_of_two_numbers():
    # Arrange
    calculator = Calculator()

    # Act
    result = calculator.add(2, 3)

    # Assert
    assert result == 5
```

**Test structure (AAA pattern):**

- **Arrange**: Set up test data and objects
- **Act**: Call the function/method
- **Assert**: Verify the result

### 3. Run Test (Should Fail)

```bash
# Run tests with your test runner
pytest test_calculator.py
# or
npm test
# or
cargo test
```

**Expected:** Test fails because implementation doesn't exist yet.

If test passes before implementation, your test is wrong!

### 4. Write Minimal Implementation (Green)

Write the simplest code that makes the test pass:

```python
class Calculator:
    def add(self, a: int, b: int) -> int:
        return a + b
```

**Key:** Don't over-engineer. Just make the test pass.

### 5. Run Test (Should Pass)

```bash
pytest test_calculator.py
# PASSED ✓
```

**Expected:** Test now passes.

### 6. Refactor (Optional)

If code needs improvement, refactor while keeping tests green.

Use `/clean` command for refactoring guidance.

**Examples:**

- Extract magic numbers to constants
- Simplify complex conditionals
- Remove duplication
- Improve naming

**Run tests after each small change.**

### 7. Repeat for Next Behavior

Add tests for edge cases and additional behaviors:

```python
def test_should_handle_negative_numbers():
    calculator = Calculator()
    assert calculator.add(-5, 3) == -2
    assert calculator.add(-1, -1) == -2

def test_should_handle_zero():
    calculator = Calculator()
    assert calculator.add(0, 5) == 5
    assert calculator.add(0, 0) == 0
```

**Keep iterating:** Red → Green → Refactor → Repeat

## Mocking: Use Sparingly

**Prefer real objects when practical.** Mocks are useful but come with costs.

### When Mocks Make Sense

- External paid APIs (don't incur costs)
- Genuinely slow operations (slow database queries)
- Non-deterministic behavior (random, time, external data)
- Unavailable dependencies (third-party without test env)
- Hardware interactions (serial ports, cameras)

### Prefer Real Objects

- Internal modules (use real implementations)
- Pure functions (already deterministic)
- In-memory data structures (lists, dicts - cheap)
- Simple utilities (formatters, calculators)

**Why minimize mocking?**

- Mocks test expectations, not actual behavior
- Mocks can drift from real implementations
- Over-mocking makes tests brittle

## Test Organization

**Descriptive names:**

```python
test_should_<behavior>_when_<condition>()
```

**One concept per test:**

Multiple assertions are OK if testing the same concept:

```python
def test_should_handle_negative_numbers():
    # Related assertions about negative number behavior
    assert calculator.add(-5, 3) == -2
    assert calculator.add(-1, -1) == -2
```

**Setup/teardown:**

Use fixtures or `before_each`/`after_each` for common setup.

## Test Coverage Philosophy

- **Confidence over coverage**: 80% coverage with trusted tests > 100% with brittle ones
- **Test behavior**, not implementation details
- **Test edge cases** for critical logic
- **Don't obsess** over 100% coverage

Conciseness and clarity matter more than line count.

## Related Documentation

- [Testing Guide](~/.claude/references/testing.md) - Comprehensive testing patterns
- [Style Guide](~/.claude/references/style.md) - Code style principles

See your language-specific documentation for testing frameworks.
