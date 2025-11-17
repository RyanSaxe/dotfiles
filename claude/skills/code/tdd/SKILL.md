# Test-Driven Development (TDD) Skill

---
name: tdd
description: Test-Driven Development workflow for writing tests first before implementation. Use when implementing features where behavior should be defined by tests first, fixing bugs that need regression tests, or working with functional units that benefit from TDD approach.
---

## Quick Reference

**TDD Cycle:**
1. **Red** - Write failing test
2. **Green** - Minimal code to pass
3. **Refactor** - Improve while tests green

**Goal:** Confident, concise tests (not exhaustive test suites)

**Related:**
- [Testing guide](../../../references/testing.md) - Comprehensive testing patterns
- [Clean code](../clean/SKILL.md) - Refactoring guidance
- Language skills - Testing frameworks and patterns

---

## Core Philosophy

**Goal**: Write the most concise and clear set of tests such that you are confident your code does what you want it to do.

**NOT the goal**: Writing 500 lines of test code to test 50 lines of real code. Extensive test suites should be rare exceptions, not the norm.

---

## TDD Cycle: Red-Green-Refactor

1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code while keeping tests green ([clean code skill](../clean/SKILL.md))

Keep the cycle tight and fast - minutes, not hours.

---

## When to Use TDD

✅ **TDD is ideal for:**
- **Functional units** (pure functions, algorithms, business logic)
- Features with clear, well-defined requirements
- Bug fixes (write test that reproduces bug first)
- APIs, libraries, utility functions
- Complex logic that needs to be proven correct
- When interface/contract is clear before implementation

⚠️ **TDD is NOT ideal for:**
- **E2E tests** - write after implementation unless requested
- **Integration tests** - usually after components work individually
- **UI/visual elements** - need experimentation and visual verification
- **Exploratory prototyping** - still figuring out what to build
- **Unclear requirements** - TDD requires knowing what "correct" looks like
- **Performance optimization** - needs profiling and experimentation first
- **Glue code** - connecting components often doesn't need test-first

---

## Mocking: Use Sparingly

**Philosophy**: Prefer real objects when practical. Mocks are useful tools but come with costs (brittleness, false confidence).

### When Mocks Make Sense

- **External paid APIs**: Don't incur costs during test runs
- **Genuinely slow operations**: Database queries that slow tests significantly
- **Non-deterministic behavior**: Random numbers, current time, external data
- **Unavailable dependencies**: Third-party service without test environment
- **Hardware interactions**: Serial ports, GPIO pins, cameras

### Prefer Real Objects When

- **Internal modules**: Test with real implementations
- **Pure functions**: Already deterministic, no need to mock
- **In-memory data structures**: Lists, dicts, objects - cheap to use
- **Simple utilities**: String formatters, calculators, validators

**Why minimize mocking?**
- Mocks test expectations, not actual behavior
- Mocks can drift from real implementations
- Over-mocking makes tests brittle
- Real objects often aren't expensive in tests

**Trade-off**: Some mocking is pragmatic. Use judgment based on test speed and complexity.

---

## Test Organization

- **Descriptive names**: `test_should_<behavior>_when_<condition>()`
- **AAA pattern**: Arrange, Act, Assert
- **One concept per test**: Multiple assertions OK if testing same concept
- **Setup/teardown**: Use fixtures or `before_each`/`after_each` for common setup

---

## TDD Workflow Example

### 1. Align on Interface

```python
# What we're building:
# Function: add(a: int, b: int) -> int
# Behavior: Returns sum of two integers
# Edge cases: Handle negatives, zeros
```

### 2. Write Test First (Red)

```python
def test_should_return_sum_of_two_numbers():
    calculator = Calculator()
    result = calculator.add(2, 3)
    assert result == 5
```

### 3. Run Test (Should Fail)

```bash
pytest test_calculator.py
# FAILED - Calculator not implemented
```

### 4. Write Minimal Implementation (Green)

```python
class Calculator:
    def add(self, a: int, b: int) -> int:
        return a + b
```

### 5. Run Test (Should Pass)

```bash
pytest test_calculator.py
# PASSED
```

### 6. Refactor (If Needed)

Improve code quality while keeping tests green.
See [clean code skill](../clean/SKILL.md) for refactoring guidance.

### 7. Repeat for Edge Cases

```python
def test_should_handle_negative_numbers():
    calculator = Calculator()
    assert calculator.add(-5, 3) == -2
    assert calculator.add(-1, -1) == -2
```

Keep the cycle tight - minutes per iteration.

---

## Test Coverage Philosophy

- **Confidence over coverage**: Better 80% coverage with trusted tests than 100% with brittle ones
- **Test behavior**, not implementation details
- **Test edge cases** for critical logic
- **Don't obsess** over 100% coverage
- Conciseness and clarity matter more than line count

---

## Language-Specific Testing

For testing frameworks and patterns:
- **Python**: [python skill](../../language/python/SKILL.md) - pytest patterns
- **Lua/Neovim**: [neovim skill](../../language/neovim/SKILL.md) - mini.test patterns
- **JavaScript/TypeScript**: Check project for vitest/jest setup

Claude will auto-invoke the relevant language skill for your context.

---

## Related Resources

- [Testing guide](../../../references/testing.md) - Comprehensive patterns and philosophy
- [Clean code](../clean/SKILL.md) - Refactoring step of TDD cycle
- [Development workflow](../../../references/development.md) - Where TDD fits in process
- [Python testing](../../language/python/SKILL.md) - pytest specifics
- [Neovim testing](../../language/neovim/SKILL.md) - mini.test specifics
