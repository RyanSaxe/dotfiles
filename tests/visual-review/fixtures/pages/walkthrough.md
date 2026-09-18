```steps
1. src/client.py@main:1
   Checkout builds a ChargeRequest.
2. src/gateway.py@main:1
   The adapter posts to the gateway.
3. src/ledger/writer.py@main:1
   A receipt is appended to the ledger.
```

```chart Backoff per attempt
{ "type": "bar", "x": [1, 2, 3, 4, 5], "y": [0.5, 1, 2, 4, 8], "unit": "seconds" }
```

```choose Where next?
- The write path, from charge to ledger
- The read path, from receipt to statement
- Failure handling: retries, breaker, timeouts
```

::: added

Sandbox mode selects `MockAdapter` through one config flag.

:::
