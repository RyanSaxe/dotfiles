Three abstractions carry every charge. Everything else is glue.

```mermaid
flowchart LR
  checkout --> PaymentClient --> GatewayAdapter --> gateway
  PaymentClient --> Ledger
```

The loop lives in `src/client.py:2` and the adapter in `src/gateway.py`.
Only `RetryableError` is retried.
