# Guard Clauses Pattern

Guard clauses help reduce nesting by handling error/edge cases early and keeping the main logic at the lowest indentation level.

## The Problem: Deep Nesting

```python
def process_order(order: Order | None) -> PaymentResult | None:
    if order is not None:
        if order.is_valid():
            if order.items:
                if order.user.is_active:
                    # Main logic buried 4 levels deep
                    total = calculate_total(order.items)
                    if apply_discount(order.user):
                        total = total * 0.9
                    return process_payment(total)
                else:
                    raise ValueError("User not active")
            else:
                return None
        else:
            raise ValueError("Invalid order")
    else:
        raise ValueError("Order is None")
```

**Problems:**
- Main logic is 4-5 levels deep
- Hard to follow the happy path
- Error handling mixed with business logic
- Cognitive load is high

## The Solution: Guard Clauses

```python
def process_order(order: Order | None) -> PaymentResult | None:
    # Guard clauses - handle errors first
    if order is None:
        raise ValueError("Order is None")
    if not order.is_valid():
        raise ValueError("Invalid order")
    if not order.items:
        return None
    if not order.user.is_active:
        raise ValueError("User not active")

    # Main logic at top level - easy to read
    total = calculate_total(order.items)
    if apply_discount(order.user):
        total = total * 0.9
    return process_payment(total)
```

**Benefits:**
- Happy path is at lowest indentation (easy to scan)
- Failures happen early (fail-fast principle)
- Each guard clause is independent and clear
- Main logic stands out

## Pattern: Extract Guard Clauses

**Steps:**
1. Identify nested conditionals checking for errors/edge cases
2. Invert the conditions (if x: → if not x:)
3. Move to top of function
4. Return/raise early
5. Reduce indentation of main logic

## More Examples

### Example: Null Checks

**Before:**
```python
def get_user_email(user_id: int) -> str | None:
    user = find_user(user_id)
    if user:
        profile = user.get_profile()
        if profile:
            if profile.email:
                return profile.email.lower()
            else:
                return None
        else:
            return None
    else:
        return None
```

**After:**
```python
def get_user_email(user_id: int) -> str | None:
    user = find_user(user_id)
    if not user:
        return None

    profile = user.get_profile()
    if not profile:
        return None

    if not profile.email:
        return None

    return profile.email.lower()
```

### Example: Permission Checks

**Before:**
```python
def delete_post(post_id: int, user: User) -> bool:
    post = find_post(post_id)
    if post:
        if user.is_authenticated():
            if user.is_author(post) or user.is_admin():
                post.delete()
                return True
            else:
                raise PermissionError("Not authorized")
        else:
            raise AuthError("Not authenticated")
    else:
        raise NotFoundError("Post not found")
```

**After:**
```python
def delete_post(post_id: int, user: User) -> bool:
    post = find_post(post_id)
    if not post:
        raise NotFoundError("Post not found")

    if not user.is_authenticated():
        raise AuthError("Not authenticated")

    if not (user.is_author(post) or user.is_admin()):
        raise PermissionError("Not authorized")

    post.delete()
    return True
```

## Max Nesting Depth

**Guideline:** Keep nesting depth ≤ 3 levels

If you have deeper nesting:
1. Extract guard clauses first
2. If still deep, extract helper functions

**Example - Extracting Helper Functions:**
```python
def process_complex_data(data: DataModel) -> ResultModel:
    if not is_valid_data(data):
        raise ValueError("Invalid data")

    processed = transform_data(data)
    result = calculate_result(processed)
    return result

def is_valid_data(data: DataModel) -> bool:
    # Guard clause logic extracted to helper
    return data and data.items and len(data.items) > 0

def transform_data(data: DataModel) -> list[str]:
    # Transformation logic extracted
    return [item.upper() for item in data.items]
```

## When NOT to Use Guard Clauses

**Appropriate nesting for related logic:**
```python
def process_items(items: list[Item]) -> list[ProcessedItem]:
    results = []
    for item in items:
        if item.is_valid():
            results.append(process_item(item))
    return results
```

This is fine - the if statement is part of the loop's logic, not a guard clause.

**Don't over-extract:**
```python
# Bad - over-extracted guard clauses
def calculate(x: int, y: int) -> int:
    if not isinstance(x, int):
        raise TypeError("x must be int")
    if not isinstance(y, int):
        raise TypeError("y must be int")
    if x < 0:
        raise ValueError("x must be positive")
    if y < 0:
        raise ValueError("y must be positive")
    if x > 1000:
        raise ValueError("x too large")
    if y > 1000:
        raise ValueError("y too large")
    return x + y

# Better - group related checks
def calculate(x: int, y: int) -> int:
    validate_input(x, "x")
    validate_input(y, "y")
    return x + y

def validate_input(value: int, name: str) -> None:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be int")
    if not 0 <= value <= 1000:
        raise ValueError(f"{name} must be between 0 and 1000")
```

## Key Takeaways

1. **Fail fast**: Handle errors at the top
2. **Happy path at lowest indentation**: Makes main logic obvious
3. **Invert conditions**: `if x: [logic]` → `if not x: return/raise`
4. **Max 3 levels of nesting**: Extract beyond this
5. **Group related guards**: Don't over-extract
