# Testing

Use tests and probes freely while you build, and expect most of them to be
temporary. Delete those before you finish. Keep a small set of tests that
protect important behavior through stable interfaces, so that a different
correct implementation passes them unchanged.

## Test behavior, not implementation

Test what a caller can see, through the interface it uses. Instead of this:

```python
def test_total(mocker):
    add_line = mocker.spy(cart, "_add_line")
    cart.total([Line(qty=2, price=3.0), Line(qty=1, price=4.0)])
    assert add_line.call_count == 2
```

write this:

```python
def test_total_is_the_sum_of_its_lines():
    assert cart.total([Line(qty=2, price=3.0), Line(qty=1, price=4.0)]) == 10.0
```

The first test breaks when `total` stops calling `_add_line`, and still passes
when the total is wrong.

## Use real dependencies

Use the real dependency wherever you can. When a test can't run it, like a
network service or the clock, pass in a fake, a small working version like an
in-memory database, rather than a mock that records calls. Code that takes its
dependencies as arguments makes this easy, and `development.md` shows how to
write it.

## Choose the cases

Cover the normal path, then the edge cases and failures a caller would notice,
and name each test after the behavior it protects. When you fix a bug that could
come back, add a test that fails without the fix, through the interface where
the bug showed. A typo or a one-off mistake doesn't need one, and neither does a
change that adds no behavior.

## Keep tests away from real state

A test that runs git, starts a server or writes files works in a scratch folder,
with an environment it controls. Git exports `GIT_DIR` to hooks, so a test that
the commit hook runs must clear git's variables before it calls git, or it acts
on the real repository. Never point a test at something the user is running.
Start a throwaway instance with its own socket or folder.
