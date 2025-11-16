---
name: clean
description: Clean code principles and refactoring patterns. Use when refactoring code, improving code quality, or during the refactor phase of TDD.
---

# Clean Code Skill

Use this skill when refactoring code, improving code quality, or during the refactor phase of TDD.

## Critical Resource

**You must first read the [Style Guide](../../../references/style.md) as a critical resource.** The style guide defines what good code looks like (the target state). This skill focuses on **how to transform code** to meet those standards.

## Core Principles

- **Minimal comments**: Only when absolutely necessary - prefer self-documenting code
- **Simple solutions**: Choose the simplest approach that works - avoid over-engineering
- **Follow existing patterns**: Match the style and structure of the existing codebase
- **Readability over cleverness**: Code is read more often than it's written
- **WET over DRY**: Write Everything Twice before abstracting - don't generalize prematurely
- **Cognitive complexity matters**: Minimize mental overhead, not just line count

## Clean Code Guidelines

### Naming

- **Be descriptive**: `user_count` not `uc`, `calculate_total_price` not `calc_tp`
- **Be consistent**: If you use `get_user` in one place, don't use `fetch_user` elsewhere
- **Use domain language**: Names should match the business/problem domain
- **Avoid abbreviations**: Unless they're universally understood (e.g., `id`, `url`, `html`)

```python
# Bad
def proc_data(x: float, y: float, z: int) -> float:
    temp = x + y
    result = temp * z
    return result

# Good
def calculate_total_cost(base_price: float, tax_rate: float, quantity: int) -> float:
    price_with_tax = base_price * (1 + tax_rate)
    total_cost = price_with_tax * quantity
    return total_cost
```

### Functions

- **Do one thing**: Functions should do one thing and do it well
- **Reasonable size**: Not too small (increases call stack depth), not too large (hard to understand)
- **Fewest parameters**: Generally less is better. 8+ parameters is a code smell
  - For many related parameters, consider a context object
  - Be mindful not to create god objects - group parameters logically
- **No side effects**: Pure functions when possible (predictable, testable)

**Parameter grouping with context objects:**

```python
# Bad: Too many parameters
def create_user(
    name: str,
    email: str,
    age: int,
    address: str,
    city: str,
    state: str,
    zip_code: str,
    phone: str,
    company: str,
) -> User:
    ...

# Good: Group related parameters
from dataclasses import dataclass

@dataclass
class UserProfile:
    name: str
    email: str
    age: int

@dataclass
class Address:
    street: str
    city: str
    state: str
    zip_code: str

@dataclass
class ContactInfo:
    phone: str
    company: str

def create_user(
    profile: UserProfile,
    address: Address,
    contact: ContactInfo,
) -> User:
    ...

# Warning: Don't create a god object
# Bad: Everything dumped into one object
@dataclass
class UserCreationContext:
    # Personal info
    name: str
    age: int
    # Contact
    email: str
    phone: str
    # Address
    street: str
    city: str
    # Preferences
    theme: str
    language: str
    # ... 20 more fields
```

**When to extract a function:**
- The code is **complex enough** that naming it significantly reduces cognitive load
- You're **actually reusing it** (but write everything twice before generalizing)
- It **genuinely** makes the code easier to understand

**When NOT to extract:**
- Creating one-line wrappers just to reduce function size
- Would require jumping around to understand simple logic
- Increases cognitive complexity with deep call stacks

```python
# Bad: Over-extracted, hard to follow
def filter_active_items(items: list[dict]) -> list[dict]:
    return [item for item in items if item["status"] == "active"]

def sort_by_priority(items: list[dict]) -> list[dict]:
    return sorted(items, key=lambda x: x["priority"])

def extract_id_and_name(items: list[dict]) -> list[dict[str, str]]:
    return [{"id": item["id"], "name": item["name"]} for item in items]

def process_data(items: list[dict]) -> list[dict[str, str]]:
    active = filter_active_items(items)
    sorted_items = sort_by_priority(active)
    return extract_id_and_name(sorted_items)

# Good: Clear and straightforward
def process_data(items: list[dict]) -> list[dict[str, str]]:
    """Process items: filter active, sort by priority, extract id/name."""
    active_items = [item for item in items if item["status"] == "active"]
    sorted_items = sorted(active_items, key=lambda x: x["priority"])
    return [{"id": item["id"], "name": item["name"]} for item in sorted_items]

# Also Good: Extract only when complexity justifies it
def process_data(items: list[dict]) -> list[dict[str, str]]:
    """Process items: filter active, sort by priority, extract fields."""
    active_items = [item for item in items if item["status"] == "active"]
    sorted_items = sorted(active_items, key=lambda x: x["priority"])
    return extract_essential_fields(sorted_items)

def extract_essential_fields(items: list[dict]) -> list[dict[str, str]]:
    """Extract id and name, plus compute derived fields."""
    # This is complex enough to justify extraction
    return [
        {
            "id": item["id"],
            "name": item["name"],
            "display_name": format_display_name(item),
            "priority_label": get_priority_label(item["priority"]),
            "status_icon": STATUS_ICONS[item["status"]],
        }
        for item in items
    ]
```

### Code Structure

- **Early returns**: Reduce nesting with guard clauses
- **Avoid deep nesting**: More than 3 levels is usually a smell
- **Extract complex conditions**: Give meaningful names to boolean expressions (when it helps clarity)

```python
# Bad: Deep nesting
def process_order(order: Order | None) -> str:
    if order is not None:
        if order.is_valid():
            if order.has_items():
                if order.user.is_verified():
                    return process_payment(order)
                else:
                    return "User not verified"
            else:
                return "No items"
        else:
            return "Invalid order"
    else:
        return "No order"

# Good: Guard clauses
def process_order(order: Order | None) -> str:
    if order is None:
        return "No order"
    if not order.is_valid():
        return "Invalid order"
    if not order.has_items():
        return "No items"
    if not order.user.is_verified():
        return "User not verified"

    return process_payment(order)
```

### Comments

**Only add comments when:**
- Explaining **why** (not what) - when the reason isn't obvious
- Warning about non-obvious behavior or side effects
- Documenting public APIs
- Required by project standards (e.g., Lua/Neovim configs per global CLAUDE.md)

**Don't add comments that:**
- Restate what the code does
- Are outdated or wrong
- Could be replaced by better naming

```python
# Bad: Comment explains what (obvious from code)
# Increment counter by 1
counter += 1

# Bad: Comment could be variable name
# Check if user has admin privileges
if user.role == "admin" and user.permissions.includes("write"):
    ...

# Good: Extracted to named variable
has_admin_write_access = (
    user.role == "admin" and user.permissions.includes("write")
)
if has_admin_write_access:
    ...

# Good: Explains WHY (non-obvious)
# Use exponential backoff to avoid overwhelming the API
# after repeated failures
retry_delay = base_delay * (2 ** attempt_count)
```

### Data Structures

- **Use appropriate structures**: Dict for lookups, list for sequences, set for uniqueness
- **Immutability when possible**: Reduces bugs from unexpected mutations
- **Type hints for clarity**: Especially for complex structures (Python 3.9+ syntax)

```python
# Good: Clear structure with type hints
def aggregate_scores(
    scores: dict[str, int],
    weights: dict[str, float],
) -> dict[str, float]:
    """Calculate weighted scores."""
    return {
        name: score * weights.get(name, 1.0)
        for name, score in scores.items()
    }
```

## WET over DRY (Write Everything Twice)

**Prefer duplication over premature abstraction.**

### Write Everything Twice Before Generalizing

```python
# First occurrence - just write it
def get_user(id: int) -> User:
    if not db.is_connected():
        raise ConnectionError("Database not connected")
    return db.query("users", id)

# Second occurrence - okay to duplicate
def get_order(id: int) -> Order:
    if not db.is_connected():
        raise ConnectionError("Database not connected")
    return db.query("orders", id)

# Third occurrence - NOW consider abstracting (if it helps)
def get_product(id: int) -> Product:
    if not db.is_connected():
        raise ConnectionError("Database not connected")
    return db.query("products", id)

# Maybe extract now (but only if the pattern is truly stable)
def ensure_connection() -> None:
    if not db.is_connected():
        raise ConnectionError("Database not connected")
```

**Why WET?**
- Premature abstraction is worse than duplication
- Easier to understand concrete code than generic abstractions
- Patterns become clear after 2-3 occurrences, not 1
- Abstractions should emerge from actual needs, not theoretical ones

**When to generalize:**
- You've written it 2-3 times and the pattern is truly identical
- The abstraction **reduces** cognitive complexity (not increases it)
- You're confident the pattern won't diverge

## Refactoring Patterns

### Replace Magic Numbers

```python
# Bad
def can_access(user: User) -> bool:
    return user.age > 18

# Good
MINIMUM_AGE = 18

def can_access(user: User) -> bool:
    return user.age >= MINIMUM_AGE
```

### Extract Complex Conditions

**Only when it genuinely helps readability:**

```python
# Bad: Extracting simple condition
is_positive = x > 0
if is_positive:
    ...

# Good: Just use the condition
if x > 0:
    ...

# Good: Extract when complex
def is_eligible_for_discount(user: User, order: Order) -> bool:
    """User qualifies for discount if they're a member, have good standing,
    and order is above minimum."""
    return (
        user.is_member
        and user.account_standing == "good"
        and not user.has_outstanding_balance
        and order.total >= MINIMUM_ORDER_FOR_DISCOUNT
        and order.created_at >= user.membership_start_date
    )

if is_eligible_for_discount(user, order):
    apply_discount(order)
```

## When Refactoring

1. **Keep tests green**: Refactor while tests pass
2. **Small steps**: Make incremental changes, test frequently
3. **One thing at a time**: Don't mix refactoring with feature work
4. **Follow existing patterns**: Match the codebase style
5. **Know when to stop**: Perfect is the enemy of good
6. **Avoid premature optimization**: Make it work, make it right, then make it fast

## Language-Specific Guidelines

For language-specific clean code patterns:
- **Python**: See [python skill](../../language/python/SKILL.md)
- **Lua/Neovim**: See [neovim skill](../../language/neovim/SKILL.md) (exception: detailed comments ARE good here)

## Further Reading

- [Detailed Style Guide](../../../references/style.md)
- [Testing Guide](../../../references/testing.md)
- [Development Workflow](../../../references/development.md)
- [TDD Refactor Phase](../tdd/SKILL.md#tdd-workflow)
