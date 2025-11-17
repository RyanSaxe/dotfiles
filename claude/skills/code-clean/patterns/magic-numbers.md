# Magic Numbers Pattern

Replace unexplained numeric/string literals with named constants to make code self-documenting.

## The Problem: Magic Numbers

```python
def process_payment(amount: float, user: User) -> bool:
    if user.age < 21:
        return False

    if amount > 100:
        discount = amount * 0.1
        amount = amount - discount

    if amount < 5:
        return False

    return charge_card(amount)
```

**Problems:**
- What is 21? What is 100? What is 0.1? What is 5?
- No context for these values
- Hard to update (scattered throughout code)
- Easy to introduce typos

## The Solution: Named Constants

```python
LEGAL_PURCHASE_AGE = 21
FREE_SHIPPING_THRESHOLD = 100.0
DISCOUNT_RATE = 0.1
MINIMUM_CHARGE = 5.0

def process_payment(amount: float, user: User) -> bool:
    if user.age < LEGAL_PURCHASE_AGE:
        return False

    if amount > FREE_SHIPPING_THRESHOLD:
        discount = amount * DISCOUNT_RATE
        amount = amount - discount

    if amount < MINIMUM_CHARGE:
        return False

    return charge_card(amount)
```

**Benefits:**
- Self-documenting (names explain meaning)
- Easy to update (change in one place)
- Searchable and reusable
- Prevents typos

## When to Extract Constants

**Extract when:**
- Number/string has business meaning
- Same value used multiple times
- Value might change in future
- Meaning isn't obvious from context

**Don't extract when:**
- Meaning is obvious from context
- Used only once in obvious context
- Standard mathematical operations

## Examples of When NOT to Extract

```python
# Good - obvious meaning, don't extract
area = width * height
double_value = x * 2
first_item = items[0]

# Good - standard loop idiom
for i in range(10):
    print(i)

# Good - clear one-time use
def create_test_user() -> User:
    return User(name="Test", age=25)
```

## Language-Specific Implementation

**Python:** Module-level constants (UPPER_CASE) or enums
**TypeScript:** `const` declarations or enums
**Go:** `const` declarations
**Java:** `static final` fields or enums
**Rust:** `const` declarations

See your language-specific skill for best practices on constants and enums.

## Key Takeaways

1. **Name magic numbers** with descriptive constants
2. **Extract when meaning not obvious** from context
3. **Don't over-extract** obvious operations (x * 2, array[0])
4. **Use UPPER_CASE** naming convention for constants
5. **Consider enums** for fixed sets of values (see language skill)
