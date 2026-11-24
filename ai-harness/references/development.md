# Development

Get the behavior working first, then shape the code before you finish, so
that a reader can follow it without comments and a test can call it without
mocks.

## Start from the interface

When a change adds or changes an interface that people or other code use,
agree with the user on how it behaves, failures included, before you build
it. The tests and docs then describe the same contract. For an internal
change, follow the contracts and patterns already there.

## Write code that explains itself

Prefer clear names, type hints, local variables and small functions over
comments or docstrings that restate the code. Instead of this:

```python
def calc(vals, wts):
    """Calculate weighted mean of values using weights."""
    return sum(v * w for v, w in zip(vals, wts)) / sum(wts)
```

write this:

```python
def calculate_weighted_mean(values: list[float], weights: list[float]) -> float:
    weighted_sum = sum(value * weight for value, weight in zip(values, weights))
    total_weight = sum(weights)
    return weighted_sum / total_weight
```

Write a comment only when the code can't show the reason for itself, like
why a workaround exists or what outside constraint forced a choice.

## State machines

Avoid implicit state machines, where it's unclear what can change what.
When something has states, one component owns them and their valid
transitions, consistent with the domain model. Instead of this:

```python
post.published = True                 # in the publish handler
post.url = slug_url(post.title)       # in a background job
if not post.published:                # in the editor, and every other caller
    post.body = new_body
```

write this:

```python
@dataclass(frozen=True)
class Draft:
    title: str
    body: str

@dataclass(frozen=True)
class Published:
    title: str
    body: str
    url: str
    published_at: datetime

def edit(post: Draft, body: str) -> Draft: ...
def publish(post: Draft, at: datetime) -> Published: ...
```

Only a draft can be edited or published, and only `publish` makes a
published post.

## Functional style and dependency injection

Most code isn't a state machine. Write it in a functional style, with pure
functions for the logic and side effects at the edges, and pass dependencies
in as arguments (dependency injection). Instead of this:

```python
def step(state: Fetching | Parsing | Saving, *, api, db) -> Fetching | Parsing | Saving | Done: ...
```

write this:

```python
def import_orders(since: datetime, *, api: OrdersApi, db: Database) -> ImportReport:
    orders = [parse_order(row) for row in api.fetch(since)]
    valid, rejected = validate(orders)
    db.save(valid)
    return ImportReport(saved=len(valid), rejected=rejected)
```

A test can call `validate` with plain values, and call `import_orders` with
a fake API and an in-memory database. Ask for the smallest dependency that
works, a callable for one operation and a protocol for several methods; reserve
an `ABC` for subclasses that share real base behavior, and check closed unions
exhaustively with `assert_never`. When a test needs a long setup or many mocks,
the code is too coupled, so fix its boundaries rather than the test.

## Boundaries

Depend on stable contracts, not on how another component happens to work.
Accept a little duplication over a shared abstraction that couples unrelated
behavior. Don't catch an error just to keep going unless recovering is part
of the behavior.

## Performance

Make the code correct and clear first. When performance matters, profile the
real workload and optimize what the profile shows is slow.
