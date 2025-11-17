---
name: clean
description: Clean code refactoring workflow. Use when you see nested conditionals, unclear naming, large functions (>50 lines), high cognitive complexity, magic numbers, or during TDD refactor phase. Transforms working code into maintainable code.
---

## TL;DR

**[READ FIRST]** → [Style Guide](../../../references/style.md) - Defines what good code looks like

This skill: **How to transform working code into maintainable code**

**Quick reminders:**

- Descriptive names, guard clauses, small functions
- WET > DRY (write twice before abstracting)
- Keep tests green throughout
- See `skills/language/` for language-specific patterns

---

## Core Principles

1. **Self-documenting code** - Names explain intent, comments explain why
2. **Simple > clever** - Obvious beats elegant
3. **One thing well** - Functions have single responsibility
4. **Low cognitive complexity** - Minimize mental overhead
5. **WET > DRY** - Duplicate twice before abstracting
6. **Follow existing patterns** - Match codebase style

[Full principles →](../../../references/style.md#core-principles)

---

## Refactoring Workflow

1. ✅ **Tests are green** before starting
2. 🔨 **One small change** at a time
3. ✅ **Run tests** after each change
4. 🔁 **Repeat** until clean
5. 🛑 **Stop when good enough** (perfect is enemy of good)

---

## Common Refactoring Patterns

### 1. Descriptive Naming

```python
# Bad
def proc(x: float, y: float, z: int) -> float:
    tmp = x * y
    return tmp + z

# Good
def calculate_total_cost(unit_price: float, quantity: int, shipping: float) -> float:
    subtotal = unit_price * quantity
    return subtotal + shipping
```

**Pattern:** Use domain language, full words, clear intent.

---

### 2. Extract Guard Clauses

```python
# Bad - nested
def process_order(order: Order | None) -> str:
    if order is not None:
        if order.is_valid():
            if order.has_items():
                return process_payment(order)

# Good - guard clauses
def process_order(order: Order | None) -> str:
    if order is None:
        return "No order"
    if not order.is_valid():
        return "Invalid order"
    if not order.has_items():
        return "No items"

    return process_payment(order)
```

**Pattern:** Fail fast, keep happy path at lowest indentation level.
**Max nesting:** 3 levels (more = extract function).

[More guard clause examples →](patterns/guard-clauses.md)

---

### 3. Group Related Parameters

```python
# Bad - 9 parameters
def create_user(name: str, email: str, age: int, street: str,
                city: str, state: str, zip_code: str, phone: str, company: str) -> User:
    ...

# Good - grouped
from dataclasses import dataclass

@dataclass
class Address:
    street: str
    city: str
    state: str
    zip_code: str

def create_user(name: str, email: str, age: int, address: Address,
                phone: str, company: str) -> User:
    ...
```

**When to group:**

- 4+ related parameters → consider grouping
- 8+ parameters → definitely group (code smell)

[More parameter grouping patterns →](patterns/parameter-grouping.md)

---

### 4. Replace Magic Numbers

```python
# Bad
if user.age >= 21 and amount > 100:
    discount = amount * 0.1

# Good
LEGAL_AGE = 21
FREE_SHIPPING_THRESHOLD = 100.0
DISCOUNT_RATE = 0.1

if user.age >= LEGAL_AGE and amount > FREE_SHIPPING_THRESHOLD:
    discount = amount * DISCOUNT_RATE
```

**Pattern:** Named constants explain meaning and enable reuse.

[More magic number examples →](patterns/magic-numbers.md)

---

## When to Extract Functions

Extract when:

- **Cognitive complexity** is high (nested logic, many conditions)
- **Doing multiple things** (violates single responsibility)
- **Reused logic** (but write twice before extracting)
- **Natural conceptual boundary** (clear name exists)

**Don't extract when:**

- Function would be 1-2 lines (over-extraction)
- Name would just restate code
- Makes code harder to follow (deep call stacks)

```python
# Bad - over-extracted
def filter_active(items: list[dict]) -> list[dict]:
    return [item for item in items if item["status"] == "active"]

def process(items: list[dict]) -> list[dict]:
    active = filter_active(items)  # Unnecessary indirection
    return sorted(active, key=lambda x: x["priority"])

# Good - clear and direct
def process(items: list[dict]) -> list[dict]:
    """Filter active items and sort by priority."""
    active = [item for item in items if item["status"] == "active"]
    return sorted(active, key=lambda x: x["priority"])
```

---

## Comments: Only When Necessary

**Add comments when:**

- Explaining **why** (not what) - when reason isn't obvious
- Warning about non-obvious behavior
- Documenting public APIs

**Don't comment:**

- Obvious code (`counter += 1  # increment counter`)
- What better naming would explain
- Outdated/wrong information

```python
# Bad - states obvious
# Loop through users
for user in users:
    process(user)

# Good - explains why
# Using exponential backoff to avoid rate limiting
for attempt in range(max_retries):
    if try_request():
        break
    sleep(2 ** attempt)
```

[Full comment philosophy →](../../../references/style.md#comments)

---

## WET Over DRY

**Principle:** Duplicate code 2-3 times before abstracting.

**Why:** Premature abstraction is worse than duplication.

- **First time:** Write it
- **Second time:** Duplicate (notice pattern)
- **Third time:** NOW consider abstracting (pattern is clear)

```python
# Write it twice first...
def get_user(id: int) -> User:
    if not db.is_connected():
        raise ConnectionError()
    return db.query("users", id)

def get_order(id: int) -> Order:
    if not db.is_connected():
        raise ConnectionError()
    return db.query("orders", id)

# Third time - extract if pattern is stable
def ensure_connection() -> None:
    if not db.is_connected():
        raise ConnectionError()
```

**When to abstract:**

- 3+ duplications AND pattern is obvious
- Abstraction makes code clearer (not more complex)
- Confident pattern won't diverge

---

## When NOT to Refactor

- ❌ Tests are failing (fix tests first)
- ❌ Feature is incomplete (finish, then refactor)
- ❌ Under time pressure (ship, refactor later)
- ❌ "Perfect is enemy of good" (know when to stop)
- ❌ Unclear what "better" looks like (need more context)

---

## Refactoring Red Flags

Watch for these code smells:

- Functions >50 lines
- Nesting depth >3 levels
- 8+ function parameters
- Unclear variable names (`tmp`, `data`, `x`)
- Repeated logic (3+ times)
- Complex conditionals (4+ conditions)
- Magic numbers scattered throughout

---

## Language-Specific Patterns

Refactoring patterns vary by language. See `skills/language/` for specifics.

Common languages: Python, Neovim/Lua, Shell

Claude will auto-invoke the relevant language skill for your context.

---

## Related Skills

- [TDD](../tdd/SKILL.md) - Refactor is phase 3 of red-green-refactor
- [Style Guide](../../../references/style.md) - Complete reference for all patterns
- [Testing Guide](../../../references/testing.md) - Keep tests green while refactoring
- [Development Workflow](../../../references/development.md) - When refactoring fits in your workflow
