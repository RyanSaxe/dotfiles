# Parameter Grouping Pattern

Group related parameters into cohesive objects to reduce parameter count and improve code clarity.

## The Problem: Too Many Parameters

```python
def create_user(
    name: str,
    email: str,
    age: int,
    street: str,
    city: str,
    state: str,
    zip_code: str,
    country: str,
    phone: str,
    is_premium: bool,
) -> User:
    # 10 parameters - overwhelming
    # Hard to remember order
    # Easy to pass wrong values
    pass
```

**Problems:**
- Too many parameters (cognitive overload)
- Hard to remember order
- Error-prone (easy to swap values)
- Difficult to add new fields
- No clear grouping of related data

## When to Group Parameters

**Guidelines:**
- **4+ related parameters** → consider grouping
- **8+ parameters** → definitely group (code smell)
- **Parameters often passed together** → create context object
- **Parameters form cohesive concept** → group them

## The Solution: Context Objects

```python
from dataclasses import dataclass

@dataclass
class Address:
    street: str
    city: str
    state: str
    zip_code: str
    country: str

@dataclass
class ContactInfo:
    email: str
    phone: str

def create_user(
    name: str,
    age: int,
    address: Address,
    contact: ContactInfo,
    is_premium: bool = False,
) -> User:
    # 5 parameters - much clearer
    # Logical grouping
    # Self-documenting
    pass
```

**Benefits:**
- Reduced parameter count (10 → 5)
- Clear relationships (related data grouped)
- Easier to extend (add to struct, not new parameter)
- Self-documenting (group names explain purpose)
- Reusable across functions

## More Examples

### API Configuration

**Before:**
```python
def make_request(
    url: str,
    method: str,
    timeout: int,
    retry_count: int,
    retry_delay: float,
    headers: dict[str, str],
    auth_token: str,
    verify_ssl: bool,
) -> Response:
    pass
```

**After:**
```python
@dataclass
class APIConfig:
    timeout: int = 30
    retry_count: int = 3
    retry_delay: float = 1.0
    verify_ssl: bool = True

@dataclass
class Auth:
    token: str
    headers: dict[str, str]

def make_request(
    url: str,
    method: str,
    config: APIConfig,
    auth: Auth,
) -> Response:
    pass
```

## When NOT to Group

**Don't force grouping of unrelated parameters:**

```python
# Bad - unrelated concepts forced together
@dataclass
class Params:
    user_id: int
    should_cache: bool
    log_level: str

def process(params: Params) -> None:
    pass

# Good - keep independent parameters separate
def process(user_id: int, should_cache: bool = True, log_level: str = "INFO") -> None:
    pass
```

**Don't over-engineer for simple cases:**

```python
# Overkill for 2-3 simple parameters used once
@dataclass
class Point:
    x: int
    y: int

def distance(p1: Point, p2: Point) -> float:
    return math.sqrt((p2.x - p1.x)**2 + (p2.y - p1.y)**2)

# This is fine
def distance(x1: int, y1: int, x2: int, y2: int) -> float:
    return math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
```

*Note: If Point is used across multiple functions, then grouping makes sense!*

## Language-Specific Implementation

**Python:** Use `dataclass` or `TypedDict` for parameter objects
**TypeScript:** Use `interface` or `type` for parameter objects
**Go:** Use `struct` for parameter objects
**Java:** Use classes or records for parameter objects

See your language-specific skill for details on best practices and idioms.

## Key Takeaways

1. **4+ related params** → consider grouping
2. **8+ params** → definitely a code smell
3. **Group cohesive concepts** (address, config, credentials)
4. **Don't force grouping** of unrelated parameters
5. **Use language idioms** - see language skill for specifics
