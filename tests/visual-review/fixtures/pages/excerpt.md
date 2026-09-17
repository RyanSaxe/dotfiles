The retry loop is five attempts with doubling backoff.

```code src/client.py@main:1-2
1  The class every caller reaches for.
2  Five attempts, then GatewayExhausted. The cap exists because
   the gateway drops idle connections at 60s.
```

The wait before attempt $n$ is

$$\text{delay}_n = \min(0.5 \cdot 2^{n}, 30)$$
