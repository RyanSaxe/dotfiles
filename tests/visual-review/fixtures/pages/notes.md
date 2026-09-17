```notes src/client.py@main
1-2  The retry loop. Up to five attempts, then GatewayExhausted.
2    Capped at 30s because the gateway drops idle connections at 60s.
```

Nothing else on this page.
