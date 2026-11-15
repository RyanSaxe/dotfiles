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

## State machines and functions

Don't write implicit state machines, where it's unclear what can change
what. When something has states, one owner changes them through named
methods, and other code calls those methods instead of setting fields
itself. The object can have as many fields as it needs. Instead of this:

```python
job.started = True                         # set by the worker
job.finished = True                        # set by a callback
if job.started and not job.finished: ...   # checked by the API
```

write this:

```python
class Job:
    status: Status  # QUEUED, RUNNING, DONE or FAILED
    report: Report | None
    error: str | None

    def start(self) -> None: ...
    def finish(self, report: Report) -> None: ...
    def fail(self, error: str) -> None: ...
```

Most code isn't a state machine at all. Steps that always run in the same order are a function. Use a functional style, with pure functions for the
logic, side effects at the edges, and dependencies passed in as arguments
(dependency injection). Instead of this:

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

A test passes a fake API and an in-memory database, and tests `validate` on
its own with plain values. Ask for the smallest dependency that works, a
callable when the function needs one operation and a protocol when it needs
several methods. When a test needs a long setup or many mocks, the code is
too coupled, so fix its boundaries rather than the test.

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
