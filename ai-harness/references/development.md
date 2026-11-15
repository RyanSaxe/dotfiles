# Development practices

Read this before designing or building a substantial change.

## Design from the interface

When the work adds or changes an interface that people or other components
use, agree with the user on how it behaves, failures included, before you
build it. The tests and docs then describe the same contract.
For an internal change, start from the contracts and patterns already there,
and don't invent a new interface to make one piece feel cleaner.

## Keep code legible

Let names, types, local variables and small functions explain the code, so a
comment or docstring doesn't have to restate it. Instead of this:

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

Keep control flow flat enough to follow, and each function and module to one
job. Write a comment only for what the code can't say, which is usually why
it is the way it is. Never wrap a single value in a class. An iteration
number is an `int`, not a dataclass with one field.

Don't write a function that only passes its arguments on to another one,
filling in defaults or renaming them. The reader has to open both to learn
what runs, and when the wrapped function takes too many arguments, the
wrapper hides that instead of fixing it. Instead of this:

```python
def send_report(report, recipients):
    return send(report, recipients, retries=3, timeout=30, format="html")
```

give `send` the defaults it should have, and call it:

```python
send(report, recipients)
```

When a call still needs many arguments, group the ones that belong together
into one value, or split the function.

## State machines

Some code waits in one of several states between calls, and something
outside it decides when it moves on. A background job is one. A worker
starts it, it runs for a while, it ends done or failed, and a caller can ask
for its result at any point. Give each state its own type, with only the
fields that exist in that state, and change the state in one place:

```python
@dataclass(frozen=True)
class Running:
    started_at: datetime

@dataclass(frozen=True)
class Done:
    report: Report

@dataclass(frozen=True)
class Failed:
    error: str

type Job = Running | Done | Failed
```

A caller has to match `Done` before it can read `report`, so it can't read a
report that doesn't exist yet. Don't write the implicit version, a `status`
string beside `report` and `error` fields that are sometimes `None`, with
every caller checking `status` first.

Steps that always run in the same order aren't a state machine. Nothing
outside waits between them or asks which one is running, so they belong in
one function. Written as a state machine, an import that fetches, parses,
validates and saves needs a type for each step and a `step` function that
moves between them:

```python
@dataclass(frozen=True)
class Fetching:
    since: datetime

@dataclass(frozen=True)
class Parsing:
    since: datetime
    rows: tuple[Row, ...]

# ...Validating and Saving, each repeating the fields before it

def step(state: Fetching | Parsing | Validating | Saving, *, api, db): ...
```

As a function, it's shorter and reads in order:

```python
def import_orders(since: datetime, *, api: OrdersApi, db: Database) -> ImportReport:
    rows = api.fetch(since)
    orders = [parse_order(row) for row in rows]
    valid, rejected = validate(orders)
    db.save(valid)
    return ImportReport(saved=len(valid), rejected=rejected)
```

## Pass dependencies in

Give a function what it depends on as arguments, as `import_orders` gets its
API client and database. Don't reach for a global, a module-level client or
an object the function builds itself. The caller then decides what the
function runs against, and a test can pass a small fake instead of patching
internals.

Ask for the smallest thing the function uses. A function that calls only
one thing takes a callable, like `fetch: Callable[[datetime], list[Row]]`.
A function that calls several methods of one object takes a protocol that
lists those methods, defined in the module that uses it. Reach for a plain
value or function before a class, and a class before a framework.

## Write code that's easy to test

Keep decisions apart from input and output. `validate` takes orders and
returns the valid ones and the rejected ones, so its test calls it with a
list and checks what comes back. `import_orders` does the fetching and
saving around it, and its test passes fakes for those. Code that makes its
decisions in the middle of reading files or calling services can only be
tested by mocking each call, and those tests break whenever the code
changes.

Keep modules out of each other's internals. When a change to one module
forces edits in another that has nothing to do with it, the two are
coupled. Put what they share behind a small interface, or copy the little
they share. A test that needs a long setup or many mocks usually means the
code's boundaries are in the wrong place, so fix the code rather than the
test. `testing.md` covers the tests themselves.

## Keep boundaries honest

Depend on stable contracts, not on how another component happens to work.
Don't add abstractions, options or fallbacks for callers that don't exist,
and accept a little duplication over a shared abstraction that couples
unrelated behavior. When an input, dependency or setting is missing, fail
clearly and as close to the boundary as you can. Don't catch an error just
to keep going unless recovering is part of the behavior.

## Measure before optimizing

Make the behavior correct and clear first. When performance matters, measure
the real workload, and let that measurement, not intuition or a micro
benchmark, choose the change.

## Leave the code easier to change

Remove complexity the change added, keep the local conventions that help,
and don't turn unrelated cleanup into part of the task.
