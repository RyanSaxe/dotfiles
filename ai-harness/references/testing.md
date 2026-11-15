# Testing

Keep a test only if it fails when something a user or another program
relies on breaks. While you build, write as many temporary tests and probes
as you like, and delete them before you finish. Code is much easier to test
when it takes its dependencies as arguments, and `development.md` explains
how to write it that way.

## Test what a caller can see

Test through the same interface that people or other code use, and check
results and effects, not which helpers ran. A different correct
implementation should pass every test unchanged.

This test checks how `import_orders` works rather than what it does. It
fails if the code saves orders one at a time instead of in one call, and it
still passes if an order goes missing:

```python
def test_import_orders():
    api = Mock(fetch=Mock(return_value=[ROW_A, ROW_B]))
    db = Mock()
    import_orders(SINCE, api=api, db=db)
    db.save.assert_called_once()
```

This one checks what callers rely on, that valid orders are saved and
invalid ones are reported:

```python
def test_import_saves_valid_orders_and_reports_the_rest():
    api = FakeOrdersApi(rows=[row(id="A1"), row(id="B2", price=None)])
    db = InMemoryDatabase()
    report = import_orders(SINCE, api=api, db=db)
    assert [order.id for order in db.orders()] == ["A1"]
    assert report.rejected == ["B2"]
```

Use the real dependency wherever you can. Substitute only what a test can't
run, like a network service, and substitute a fake, a small working version
like `InMemoryDatabase`, rather than a mock that records calls. Don't assert
an exact value unless that value is the contract.

## Choose the cases

Cover the normal path first, then the edge cases and failures a caller
would notice. A bug fix gets a regression test that fails before the fix and
passes after it, through the interface where the bug showed up. Name each
test after the behavior and the condition, so a failure says what stopped
working.

Don't add a test just because a file changed. A change that adds no
behavior is better checked by running the program.

## Keep tests away from real state

A test that runs git, starts a server or writes files works in a scratch
folder, with an environment it controls. Git exports `GIT_DIR` to hooks, so
a test that the commit hook runs must clear git's variables before it calls
git, or it acts on the real repository. Never point a test at something the
user is running. Start a throwaway instance with its own socket or folder.
