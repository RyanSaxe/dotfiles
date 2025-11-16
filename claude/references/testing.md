# Testing Guide

This document provides comprehensive testing patterns, methodologies, and best practices.

## Core Philosophy

**Tests are the absolute best form of documentation.**

Why tests are superior documentation:
- **Show actual usage**: Real inputs and outputs, not theoretical examples
- **Always up-to-date**: If they pass, they reflect current behavior
- **Executable**: Prove they work by running them
- **Show edge cases**: Document boundaries and error handling
- **Cannot become stale**: Unlike comments or docs, failing tests force updates

Write tests with documentation in mind - they're examples for future developers (including yourself).

## Testing Principles

1. **Confidence over coverage**: Goal is confidence code works, not 100% coverage
2. **Behavior over implementation**: Test what code does, not how it does it
3. **Concise and clear**: Aim for minimal tests that give maximum confidence
4. **One concept per test**: Multiple assertions are fine if testing same concept
5. **Avoid excessive tests**: 500 lines of tests for 50 lines of code is usually wrong

## Test Organization

### Test Structure (AAA Pattern)

```python
def test_should_calculate_discount_correctly():
    # Arrange: Set up test data
    price = 100.0
    discount_rate = 0.2

    # Act: Execute the behavior
    result = calculate_discount(price, discount_rate)

    # Assert: Verify the outcome
    assert result == 80.0
```

### Descriptive Test Names

Use names that explain the behavior:

```python
# Good: Descriptive names
def test_should_return_empty_list_when_no_items_match():
    ...

def test_should_raise_error_when_amount_is_negative():
    ...

def test_should_calculate_tax_correctly_for_standard_rate():
    ...

# Bad: Vague names
def test_filter():
    ...

def test_error():
    ...

def test_tax():
    ...
```

### Multiple Assertions for Single Concept

```python
# Good: Multiple assertions testing same concept (correctness of math)
def test_should_handle_various_numeric_inputs():
    calculator = Calculator()

    assert calculator.add(-5, 3) == -2
    assert calculator.add(0, 0) == 0
    assert calculator.add(-1, -1) == -2
    assert calculator.add(100, 200) == 300

# Also good: Separate tests if concepts are distinct
def test_should_handle_negative_numbers():
    assert calculate(--5, 3) == -2

def test_should_handle_zeros():
    assert calculate(0, 0) == 0
```

## When to Test

### Test These

✅ **Business logic**: Core algorithms and calculations
✅ **Public APIs**: Functions/methods other code depends on
✅ **Edge cases**: Boundary conditions and error paths
✅ **Bug fixes**: Regression tests to prevent reintroduction
✅ **Complex conditionals**: Logic with multiple branches

### Don't Test These

❌ **Framework code**: Don't test Django/Flask/etc. functionality
❌ **Third-party libraries**: Trust pytest, requests, pandas, etc.
❌ **Trivial code**: Getters/setters with no logic
❌ **Implementation details**: Private methods (test through public API)
❌ **External services**: Mock or use test doubles instead

## Test Types

### Unit Tests

Test individual functions/methods in isolation:

```python
def test_calculate_tax_returns_correct_amount():
    result = calculate_tax(amount=100.0, rate=0.08)
    assert result == 8.0
```

**Characteristics:**
- Fast (milliseconds)
- Isolated (no external dependencies)
- Deterministic (same input = same output)

### Integration Tests

Test components working together:

```python
def test_order_processing_updates_inventory():
    # Tests multiple components: order, inventory, database
    order = create_order(items=[Item("widget", quantity=5)])
    process_order(order)

    inventory = get_inventory("widget")
    assert inventory.quantity == 95  # Started at 100
```

**Characteristics:**
- Slower (seconds)
- May use databases, files, or services
- Test component interactions

### End-to-End Tests

Test complete user workflows:

```python
def test_user_can_complete_purchase():
    # Full workflow from browsing to purchase
    user = login_user("test@example.com")
    add_to_cart(user, "product-123")
    checkout(user, payment_method="credit_card")

    order = get_latest_order(user)
    assert order.status == "completed"
    assert order.items[0].product_id == "product-123"
```

**Characteristics:**
- Slowest (seconds to minutes)
- Tests entire system
- Catches integration issues
- Use sparingly (expensive to maintain)

## Testing Best Practices

### Use Fixtures for Setup

```python
import pytest

@pytest.fixture
def sample_user():
    """Provide a test user for multiple tests."""
    return User(name="Test User", email="test@example.com")

@pytest.fixture
def database():
    """Provide a clean database for each test."""
    db = create_test_database()
    yield db
    db.cleanup()

def test_user_creation(database, sample_user):
    database.save(sample_user)
    assert database.count_users() == 1
```

### Avoid Mocking Unless Necessary

**See [TDD Skill](../skills/code/tdd/SKILL.md) for comprehensive mocking guidelines.**

**Use mocks only when:**
- External paid APIs (avoid costs)
- Slow operations (database, network)
- Non-deterministic behavior (time, random)
- Unavailable services (third-party APIs)

**Prefer real objects when:**
- Testing internal code
- Pure functions
- In-memory data structures
- Simple utilities

### Test Error Cases

```python
def test_should_raise_error_for_negative_amount():
    with pytest.raises(ValueError, match="Amount must be positive"):
        withdraw(account, amount=-50)

def test_should_return_none_for_missing_user():
    result = find_user(user_id=99999)
    assert result is None
```

### Keep Tests Independent

```python
# Bad: Tests depend on execution order
def test_create_user():
    global user
    user = create_user("test@example.com")

def test_update_user():  # Depends on previous test!
    user.name = "Updated Name"
    save_user(user)

# Good: Each test is independent
def test_create_user():
    user = create_user("test@example.com")
    assert user.email == "test@example.com"

def test_update_user():
    user = create_user("test@example.com")
    user.name = "Updated Name"
    save_user(user)
    assert user.name == "Updated Name"
```

## Test-Driven Development (TDD)

For comprehensive TDD workflow, see [TDD Skill](../skills/code/tdd/SKILL.md).

**Brief overview:**
1. Write test defining desired behavior (Red)
2. Write minimal code to pass (Green)
3. Refactor while keeping tests green

**When TDD is ideal:**
- Clear requirements
- Functional units (pure functions, algorithms)
- Bug fixes (test the bug first)
- APIs and libraries

**When TDD is not ideal:**
- Exploratory work
- UI/visual elements
- Unclear requirements
- E2E or integration tests

## Language-Specific Testing

### Python (pytest)

See [Python Skill](../skills/language/python/SKILL.md) for detailed patterns.

```python
# Basic test
def test_addition():
    assert add(2, 3) == 5

# Fixtures
@pytest.fixture
def calculator():
    return Calculator()

# Parametrize for multiple inputs
@pytest.mark.parametrize("a,b,expected", [
    (2, 3, 5),
    (-1, 1, 0),
    (0, 0, 0),
])
def test_addition_multiple_inputs(a, b, expected):
    assert add(a, b) == expected
```

### Lua/Neovim (mini.test)

See [Neovim Skill](../skills/language/neovim/SKILL.md) for detailed patterns.

```lua
describe("module functionality", function()
  before_each(function()
    -- Setup
  end)

  it("performs expected behavior", function()
    assert.equal(expected, actual)
  end)
end)
```

## Test Coverage

### What Coverage Means

- **Line coverage**: Which lines executed during tests
- **Branch coverage**: Which conditional branches taken
- **Path coverage**: Which execution paths followed

### Coverage Guidelines

- **Aim for high coverage of business logic** (80%+)
- **Don't obsess over 100% coverage** - diminishing returns
- **Focus on important code paths** - not every getter/setter
- **Use coverage to find untested code** - not as a goal itself

### Running Coverage

```bash
# Python
pytest --cov=mymodule --cov-report=html

# View report
open htmlcov/index.html
```

## Testing Anti-Patterns

### Don't Test Implementation Details

```python
# Bad: Tests internal implementation
def test_uses_quicksort():
    sorter = Sorter()
    sorter.sort([3, 1, 2])
    assert sorter.algorithm == "quicksort"  # Implementation detail!

# Good: Tests behavior
def test_sorts_items_in_ascending_order():
    result = sort([3, 1, 2])
    assert result == [1, 2, 3]
```

### Don't Write Brittle Tests

```python
# Bad: Breaks when non-essential details change
def test_user_to_json():
    user = User(name="Alice", email="alice@example.com")
    json_str = user.to_json()
    # Brittle: Exact string matching including whitespace
    assert json_str == '{"name": "Alice", "email": "alice@example.com"}'

# Good: Tests essential behavior
def test_user_to_json():
    user = User(name="Alice", email="alice@example.com")
    result = json.loads(user.to_json())
    assert result["name"] == "Alice"
    assert result["email"] == "alice@example.com"
```

### Don't Write Tests That Are Too Complex

```python
# Bad: Test is as complex as the code
def test_complex_calculation():
    # 50 lines of setup
    # Complex mocking
    # Multiple assertions with unclear relationships
    ...

# Good: Simple, focused test
def test_calculates_compound_interest():
    result = calculate_compound_interest(
        principal=1000,
        rate=0.05,
        periods=2
    )
    assert result == 1102.50
```

## Running Tests

### Basic Commands

```bash
# Python (pytest)
pytest                          # Run all tests
pytest tests/test_module.py    # Run specific file
pytest -v                       # Verbose output
pytest -k "test_user"          # Run tests matching pattern
pytest --lf                     # Run last failed tests

# Lua/Neovim (mini.test)
nvim -l tests/minit.lua        # Run all tests
```

### Continuous Testing

```bash
# Python with pytest-watch
ptw

# Or with pytest-xdist for parallel execution
pytest -n auto
```

## Related Guides

- [TDD Skill](../skills/code/tdd/SKILL.md) - Test-driven development workflow
- [Style Guide](style.md) - Code style standards
- [Development Workflow](development.md) - Development process
- [Python Testing](../skills/language/python/SKILL.md) - Python-specific patterns
- [Neovim Testing](../skills/language/neovim/SKILL.md) - Lua/Neovim testing patterns
