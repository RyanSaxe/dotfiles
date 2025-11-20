# Code Style Guide

This document defines what good code looks like - the standards, conventions, and patterns to follow when writing code.

NOTE: the code examples in this file are python, but they apply to all languages. Any language that wants to deviate will specify in the corresponding skill located in skills/lang-[name-of-language].

## Core Principles

Good code exhibits these qualities:

1. **Self-documenting**: Names and structure make the code's purpose clear
2. **Simple**: Solves problems with the simplest approach that works
3. **Consistent**: Follows existing patterns in the codebase
4. **Readable**: Optimized for humans reading it, not just machines running it
5. **Minimal cognitive load**: Easy to understand without jumping around

## Naming Conventions

### Variables and Functions

**Rules:**

- Use descriptive names that reveal intent
- Use consistent terminology throughout
- Match domain/business language
- Avoid abbreviations unless universally understood (id, url, html, api, etc.)
- Use verbs for functions, nouns for data

**Good naming:**

```python
# Variables: Clear nouns
user_count = len(users)
total_price = calculate_price(items)
is_authenticated = check_auth(user)

# Functions: Clear verbs + object
def calculate_total_cost(base_price: float, tax_rate: float, quantity: int) -> float:
    price_with_tax = base_price * (1 + tax_rate)
    total_cost = price_with_tax * quantity
    return total_cost

def validate_email(email: str) -> bool:
    return EMAIL_PATTERN.match(email) is not None
```

**Bad naming:**

```python
# Too short, unclear
def proc_data(x, y, z):
    temp = x + y
    result = temp * z
    return result

# Inconsistent terminology
def get_user(id): ...
def fetch_customer(id): ...  # Use 'get' everywhere or 'fetch' everywhere

# Unnecessary abbreviations
usr_cnt = len(usrs)
calc_tot_prc = calc_price(itms)
```

### Constants

Use SCREAMING_SNAKE_CASE for constants:

```python
MAX_RETRY_ATTEMPTS = 3
DEFAULT_TIMEOUT_SECONDS = 30
API_BASE_URL = "https://api.example.com"
```

### Classes and Types

Use CamelCase for classes and types:

```python
class UserAccount:
    pass

class PaymentProcessor:
    pass

@dataclass
class OrderSummary:
    total: float
    item_count: int
```

## Function Design

### Single Responsibility

Each function should do one thing and do it well:

```python
# Good: One clear purpose
def calculate_discount(price: float, discount_rate: float) -> float:
    return price * (1 - discount_rate)

def apply_discount_to_order(order: Order, discount_rate: float) -> Order:
    for item in order.items:
        item.price = calculate_discount(item.price, discount_rate)
    return order

# Bad: Does too many things
def process_order(order: Order, discount_rate: float) -> Order:
    # Validates
    if not order.is_valid():
        raise ValueError("Invalid order")

    # Applies discount
    for item in order.items:
        item.price = item.price * (1 - discount_rate)

    # Saves to database
    save_to_database(order)

    # Sends email
    send_confirmation_email(order.user)

    return order
```

<IMPORTANT>Do not go overboard here. Functions with only a few lines that call other functions can be problematic and increase cognitive complexity. This principal is NOT about size of the function, but just about avoiding having a function do too many things.</IMPORTANT>

### Parameter Count

**Ideal:** 0-3 parameters
**Acceptable:** 4-7 parameters
**Code smell:** 8+ parameters

For many related parameters, group them logically:

```python
# Bad: Too many parameters
def create_user(
    name: str,
    email: str,
    age: int,
    street: str,
    city: str,
    state: str,
    zip_code: str,
    phone: str,
    company: str,
) -> User:
    ...

# Good: Grouped logically
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
```

**Warning:** Don't create god objects that dump everything into one parameter:

```python
# Bad: God object
@dataclass
class UserCreationContext:
    name: str
    email: str
    age: int
    street: str
    city: str
    state: str
    zip_code: str
    phone: str
    company: str
    # ... 20 more unrelated fields
```

### Pure Functions

Prefer pure functions (no side effects, deterministic):

```python
# Good: does not mutate the input list
def square(items: list[float]) -> list[float]:
    return [item ** 2 for item in items]

# Acceptable: Side effect is the point
def save_user(user: User) -> None:
    database.save(user)

# Bad: mutates the input list
def square(items: list[float]) -> list[float]:
    for i in range(len(items)):
      items[i] = items[i] ** 2
    return items
```

## Code Structure

### Early Returns (Guard Clauses)

Use early returns to reduce nesting:

```python
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
```

### Nesting Depth

**Maximum recommended:** 3 levels of nesting
**Ideal:** 1-2 levels

```python
# Good: Flat structure
def process_items(items: list[Item]) -> list[Result]:
    results = []
    for item in items:
        if not item.is_valid():
            continue

        result = process_item(item)
        results.append(result)

    return results

# Bad: Deep nesting (4 levels)
def process_items(items: list[Item]) -> list[Result]:
    results = []
    for item in items:                    # Level 1
        if item.is_valid():               # Level 2
            if item.requires_special():   # Level 3
                if item.has_permission(): # Level 4
                    result = special_process(item)
                    results.append(result)
    return results
```

### Named Conditions

Extract complex conditions into named variables:

```python
# Good: Named conditions
def can_process_order(user: User, order: Order) -> bool:
    is_verified_user = user.is_verified and user.account_status == "active"
    is_valid_order = order.is_valid() and order.has_items()
    has_sufficient_balance = user.balance >= order.total

    return is_verified_user and is_valid_order and has_sufficient_balance

# Bad: Complex inline condition
def can_process_order(user: User, order: Order) -> bool:
    return (user.is_verified and user.account_status == "active" and
            order.is_valid() and order.has_items() and
            user.balance >= order.total)
```

## Comments

### When to Comment

**Do comment when:**

1. **Explaining WHY** (not what):

```python
# Good: Explains non-obvious reasoning
# Use exponential backoff to avoid overwhelming the API
# after repeated failures
retry_delay = base_delay * (2 ** attempt_count)
```

2. **Warning about side effects:**

```python
# Warning: This modifies the global cache
# Call clear_cache() before running tests
def update_user_preferences(user_id: int, prefs: dict) -> None:
    GLOBAL_CACHE[user_id] = prefs
```

3. **Documenting public APIs:**

```python
def calculate_compound_interest(
    principal: float,
    rate: float,
    periods: int
) -> float:
    """
    Calculate compound interest.

    Args:
        principal: Initial investment amount
        rate: Interest rate per period (e.g., 0.05 for 5%)
        periods: Number of compounding periods

    Returns:
        Final amount after compound interest
    """
    return principal * (1 + rate) ** periods
```

### When NOT to Comment

**Don't comment when:**

1. **Restating the obvious:**

```python
# Bad: Comment adds no value
# Increment counter by 1
counter += 1

# Loop through users
for user in users:
    ...
```

2. **Code is self-documenting:**

```python
# Bad: Comment should be function name
# Check if user has admin write permissions
if user.role == "admin" and user.permissions.includes("write"):
    ...

# Good: Named function
def has_admin_write_access(user: User) -> bool:
    return user.role == "admin" and user.permissions.includes("write")

if has_admin_write_access(user):
    ...
```

3. **Outdated or wrong information:**

```python
# Bad: Outdated comment
# Returns a list of users
def get_users() -> dict[int, User]:  # Actually returns a dict now!
    ...
```

## Data Structures

### Choose Appropriate Types

```python
# Use dict for key-value lookups
user_by_id: dict[int, User] = {user.id: user for user in users}

# Use list for ordered sequences
ordered_items: list[Item] = sorted(items, key=lambda x: x.priority)

# Use set for uniqueness/membership testing
seen_ids: set[int] = {item.id for item in items}

# Use tuple for immutable, heterogeneous data
coordinates: tuple[float, float] = (lat, lon)
```

### Type Hints

Always use type hints for function signatures:

```python
def process_data(
    items: list[dict[str, Any]],
    weights: dict[str, float],
) -> dict[str, float]:
    return {
        name: score * weights.get(name, 1.0)
        for name, score in items
    }
```

## Magic Numbers

Replace magic numbers with named constants or parameters:

```python
# Bad: Magic numbers
if user.age > 18 and order.total < 100:
    apply_discount(order, 0.1)

# Good: Named constants
MINIMUM_AGE = 18
DISCOUNT_THRESHOLD = 100
DISCOUNT_RATE = 0.1

if user.age >= MINIMUM_AGE and order.total < DISCOUNT_THRESHOLD:
    apply_discount(order, DISCOUNT_RATE)
```

## Error Handling

### Fail Fast Principle

Let errors surface immediately rather than hiding them:

```python
# Good: Fail fast - let error bubble up
def divide(a: float, b: float) -> float:
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b

# Good: Explicit validation
def process_user(user_id: int) -> User:
    user = find_user(user_id)
    if user is None:
        raise ValueError(f"User {user_id} not found")
    return user

# Bad: Swallowing errors
def divide(a: float, b: float) -> float:
    try:
        return a / b
    except ZeroDivisionError:
        return 0  # Hides the error!
```

### Avoid try/except Unless Necessary

Only catch exceptions when you have a specific reason:

```python
# Good: Only catch when you can handle it meaningfully
def load_config() -> dict:
    try:
        with open("config.json") as f:
            return json.load(f)
    except FileNotFoundError:
        # Meaningful fallback: use default config
        return DEFAULT_CONFIG
    # Let other errors (JSONDecodeError, PermissionError) bubble up

# Bad: Catching too broadly
def load_config() -> dict:
    try:
        with open("config.json") as f:
            return json.load(f)
    except Exception:  # Catches everything, including bugs!
        return {}

# Good: No try/except needed - let it fail
def calculate_total(items: list[Item]) -> float:
    return sum(item.price for item in items)
    # If items is None or item.price fails, that's a real error - let it bubble
```

**When to use try/except:**

- Interacting with external systems (files, network, databases)
- Providing meaningful fallbacks
- Converting one error type to another more appropriate one
- Adding context to errors before re-raising

**When NOT to use try/except:**

- "Just in case" error handling
- Hiding bugs
- As a substitute for proper validation

### Only Validate Necessary Cases

```python
# Good: Return None for missing data
def find_user(user_id: int) -> User | None:
    return users.get(user_id)

# Good: Raise for invalid inputs
def withdraw(account: Account, amount: float) -> None:
    if amount < 0:
        raise ValueError("Amount must be positive")
    if amount > account.balance:
        raise ValueError("Insufficient funds")
    account.balance -= amount

# Bad: Excessive validation (code smell)
def withdraw(account: Account, amount: float) -> None:
    if account is None:
        raise ValueError("Account cannot be None")  # Type system handles this
    if not isinstance(amount, (int, float)):
        raise TypeError("Amount must be numeric")  # Type hints handle this
    if amount <= 0:
        raise ValueError("Amount must be positive")
    if amount > account.balance:
        raise ValueError("Insufficient funds")
    if amount > 1000000:
        raise ValueError("Amount too large")  # Unrealistic edge case
    if account.balance < 0:
        raise ValueError("Account corrupted")  # "Can't happen" defensive check
    if not hasattr(account, 'balance'):
        raise AttributeError("Invalid account")  # Already checked above
    account.balance -= amount
```

## Functions vs Classes

### Prefer Functions Over Classes

**Default choice: Functions**

Functions are simpler, easier to test, and more composable:

```python
# Good: Simple functions
def calculate_tax(amount: float, rate: float) -> float:
    return amount * rate

def format_currency(amount: float) -> str:
    return f"${amount:.2f}"

def calculate_total(subtotal: float, tax_rate: float) -> str:
    tax = calculate_tax(subtotal, tax_rate)
    total = subtotal + tax
    return format_currency(total)
```

### When to Use Classes

Use classes when you need to:

1. **Maintain state across multiple operations:**

```python
class ShoppingCart:
    def __init__(self):
        self.items: list[Item] = []
        self.total: float = 0.0

    def add_item(self, item: Item) -> None:
        self.items.append(item)
        self.total += item.price

    def remove_item(self, item_id: int) -> None:
        item = self.find_item(item_id)
        if item:
            self.items.remove(item)
            self.total -= item.price
```

2. **Group related behavior with shared data:**

```python
class DatabaseConnection:
    def __init__(self, connection_string: str):
        self.connection = connect(connection_string)
        self.transaction = None

    def begin_transaction(self) -> None:
        self.transaction = self.connection.transaction()

    def commit(self) -> None:
        if self.transaction:
            self.transaction.commit()

    def rollback(self) -> None:
        if self.transaction:
            self.transaction.rollback()
```

3. **Need instances with different configurations:**

```python
class APIClient:
    def __init__(self, base_url: str, api_key: str):
        self.base_url = base_url
        self.api_key = api_key
        self.session = requests.Session()

    def get(self, endpoint: str) -> dict:
        url = f"{self.base_url}/{endpoint}"
        return self.session.get(url, headers={"Authorization": self.api_key}).json()

# Multiple instances with different configs
prod_client = APIClient("https://api.prod.com", prod_key)
test_client = APIClient("https://api.test.com", test_key)
```

4. **Implementing interfaces/protocols:**

```python
class PaymentProcessor(Protocol):
    def process_payment(self, amount: float) -> bool:
        ...

class StripeProcessor:
    def process_payment(self, amount: float) -> bool:
        # Stripe implementation
        ...

class PayPalProcessor:
    def process_payment(self, amount: float) -> bool:
        # PayPal implementation
        ...
```

### When NOT to Use Classes

Don't use classes for:

```python
# Bad: Class with only one method (use a function)
class TaxCalculator:
    def calculate(self, amount: float, rate: float) -> float:
        return amount * rate

# Good: Just a function
def calculate_tax(amount: float, rate: float) -> float:
    return amount * rate

# Bad: Class with no state (use functions)
class MathUtils:
    def add(self, a: float, b: float) -> float:
        return a + b

    def multiply(self, a: float, b: float) -> float:
        return a * b

# Good: Just functions
def add(a: float, b: float) -> float:
    return a + b

def multiply(a: float, b: float) -> float:
    return a * b
```

### Composition Over Inheritance

When you do use classes, prefer composition over inheritance:

```python
# Bad: Deep inheritance hierarchy
class Animal:
    def move(self):
        ...

class Mammal(Animal):
    def feed_young(self):
        ...

class Dog(Mammal):
    def bark(self):
        ...

class ServiceDog(Dog):  # Getting complex!
    def assist(self):
        ...

# Good: Composition with functions (not single-method classes!)
from typing import Callable
from dataclasses import dataclass

# Simple function signatures for behaviors
MovementBehavior = Callable[[], str]
VocalizationBehavior = Callable[[], str]

# Behavior implementations as functions
def walk() -> str:
    return "Walking on four legs"

def bark() -> str:
    return "Woof!"

def meow() -> str:
    return "Meow!"

# Compose behaviors into animals
@dataclass
class Animal:
    name: str
    movement: MovementBehavior
    vocalization: VocalizationBehavior

    def move(self) -> str:
        return self.movement()

    def make_sound(self) -> str:
        return self.vocalization()

# Create animals by composing functions
dog = Animal(name="Dog", movement=walk, vocalization=bark)
cat = Animal(name="Cat", movement=walk, vocalization=meow)

# Or with Protocols for more complex behaviors
class MovementBehavior(Protocol):
    def move(self) -> str: ...

class VocalizationBehavior(Protocol):
    def vocalize(self) -> str: ...

def walk() -> str:
    return "Walking"

def bark() -> str:
    return "Woof!"

@dataclass
class Animal:
    name: str
    movement_fn: Callable[[], str]
    vocalization_fn: Callable[[], str]

dog = Animal(name="Dog", movement_fn=walk, vocalization_fn=bark)
```

**Inheritance is acceptable when:**

- You're implementing interfaces/protocols
- You're extending framework classes (Django models, etc.)
- There's a clear "is-a" relationship and shallow hierarchy (1-2 levels)

**Language considerations:**

- Python: Functions are first-class, prefer them
- Lua: Tables and functions are often more idiomatic than classes
- Java/C#: Classes are more fundamental, but still prefer simple over complex hierarchies

## Related Guides

- [Clean Code Skill](../skills/code/clean/SKILL.md) - How to transform code to meet these standards
- [Testing Guide](testing.md) - Testing serves as executable documentation
- [Development Workflow](development.md) - Development process and best practices
