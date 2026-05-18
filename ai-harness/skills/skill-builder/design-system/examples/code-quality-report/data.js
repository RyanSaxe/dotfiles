// Mock findings inlined for file:// compatibility (fetch is blocked from local files).
// 12 findings across all five severity levels in a fictional payment-service repo.
// Generated 2026-05-04.

const AUDIT_META = {
  branch: "feature/payment-rewrite",
  base: "main",
  commit: "8f3a2c1",
  generated: "2026-05-04 14:22 UTC",
  files_scanned: 47,
  files_with_findings: 9,
};

const FINDINGS = [
  {
    id: "F-001",
    severity: "critical",
    rule: "B105",
    title: "Hardcoded Stripe secret key in source",
    file: "src/payments/stripe_client.py",
    lines: "14",
    description:
      "A live Stripe secret key is committed to the repository. Anyone with read access can charge arbitrary cards or issue refunds. Rotate the key immediately and load it from a secret store.",
    language: "python",
    bad: `import stripe

# TODO: move to env when we have time
STRIPE_SECRET = "sk_live_REDACTED_EXAMPLE_NOT_A_KEY"
stripe.api_key = STRIPE_SECRET`,
    good: `import os
import stripe

stripe.api_key = os.environ["STRIPE_SECRET_KEY"]`,
    status: "open",
  },
  {
    id: "F-002",
    severity: "critical",
    rule: "B608",
    title: "SQL injection via string-formatted query",
    file: "src/payments/refunds.py",
    lines: "42-44",
    description:
      "User-controlled `user_id` is interpolated into the SQL string. An attacker can read or modify arbitrary rows in the refunds table. Use a parameterized query.",
    language: "python",
    bad: `def list_refunds(user_id: str) -> list[Refund]:
    rows = db.execute(
        f"SELECT * FROM refunds WHERE user_id = {user_id}"
    )
    return [Refund(**row) for row in rows]`,
    good: `def list_refunds(user_id: str) -> list[Refund]:
    rows = db.execute(
        "SELECT * FROM refunds WHERE user_id = %s",
        (user_id,),
    )
    return [Refund(**row) for row in rows]`,
    status: "open",
  },
  {
    id: "F-003",
    severity: "high",
    rule: "CWE-352",
    title: "Stripe webhook accepts unsigned payloads",
    file: "src/api/webhooks.py",
    lines: "23-31",
    description:
      "The webhook endpoint trusts the request body without verifying Stripe's signature header. An attacker can POST forged events (e.g., a fake `payment_succeeded`) and trigger downstream fulfillment.",
    language: "python",
    bad: `@app.post("/webhooks/stripe")
def handle_webhook(payload: dict):
    event_type = payload["type"]
    if event_type == "payment_intent.succeeded":
        fulfill_order(payload["data"]["object"]["metadata"]["order_id"])
    return {"received": True}`,
    good: `@app.post("/webhooks/stripe")
def handle_webhook(request: Request):
    sig = request.headers["stripe-signature"]
    event = stripe.Webhook.construct_event(
        request.body, sig, settings.STRIPE_WEBHOOK_SECRET,
    )
    if event.type == "payment_intent.succeeded":
        fulfill_order(event.data.object.metadata["order_id"])
    return {"received": True}`,
    status: "open",
  },
  {
    id: "F-004",
    severity: "high",
    rule: "CWE-532",
    title: "Full card number written to application logs",
    file: "src/payments/charge.py",
    lines: "88",
    description:
      "The full PAN is interpolated into a log line. Logs are shipped to the central aggregator and retained for 90 days, putting the system out of PCI scope. Log only the last four digits.",
    language: "python",
    bad: `logger.info(f"Charging card ending in {card.number} for {amount}")`,
    good: `logger.info(f"Charging card ending in {card.last4} for {amount}")`,
    status: "resolved",
  },
  {
    id: "F-005",
    severity: "medium",
    rule: "PERF401",
    title: "N+1 query loading user for each transaction",
    file: "src/api/transactions.py",
    lines: "118-124",
    description:
      "For a 200-row response this issues 201 queries (1 for the list + 1 per transaction). Use a join or a single `WHERE user_id IN (...)` query and group in Python.",
    language: "python",
    bad: `txns = Transaction.query.filter_by(account_id=acct.id).all()
result = []
for t in txns:
    user = User.query.get(t.user_id)
    result.append({"txn": t, "user_email": user.email})
return result`,
    good: `txns = (
    Transaction.query
    .filter_by(account_id=acct.id)
    .options(joinedload(Transaction.user))
    .all()
)
return [{"txn": t, "user_email": t.user.email} for t in txns]`,
    status: "open",
  },
  {
    id: "F-006",
    severity: "medium",
    rule: "RACE",
    title: "Read-modify-write on balance without lock",
    file: "src/payments/balance.py",
    lines: "55-62",
    description:
      "Two concurrent requests can both read the same balance and each write back `balance - amount`, double-spending the funds. Use `SELECT ... FOR UPDATE` inside a transaction or move to an atomic decrement.",
    language: "python",
    bad: `def debit(account_id: int, amount: Decimal) -> None:
    acct = db.session.query(Account).get(account_id)
    if acct.balance < amount:
        raise InsufficientFunds()
    acct.balance -= amount
    db.session.commit()`,
    good: `def debit(account_id: int, amount: Decimal) -> None:
    with db.session.begin():
        acct = (
            db.session.query(Account)
            .filter_by(id=account_id)
            .with_for_update()
            .one()
        )
        if acct.balance < amount:
            raise InsufficientFunds()
        acct.balance -= amount`,
    status: "open",
  },
  {
    id: "F-007",
    severity: "medium",
    rule: "VAL",
    title: "No validation on payment amount",
    file: "src/api/payments.py",
    lines: "31",
    description:
      "`amount` is taken from the request body without bounds. A negative amount creates an unintended refund; `inf` or `NaN` will crash the downstream serializer. Validate at the boundary.",
    language: "python",
    bad: `@app.post("/payments")
def create_payment(amount: float, currency: str):
    return charge_card(amount=amount, currency=currency)`,
    good: `@app.post("/payments")
def create_payment(amount: Decimal = Body(..., gt=0, le=1_000_000), currency: str = Body(..., regex="^[A-Z]{3}$")):
    if not amount.is_finite():
        raise HTTPException(400, "amount must be finite")
    return charge_card(amount=amount, currency=currency)`,
    status: "open",
  },
  {
    id: "F-008",
    severity: "low",
    rule: "STYLE",
    title: "Inconsistent error response shape across endpoints",
    file: "src/api/auth.py",
    lines: "67, 92, 134",
    description:
      "Three endpoints return errors as `{error: \"...\"}`, `{message: \"...\"}`, and `{detail: \"...\"}` respectively. The mobile client special-cases each. Standardize on the project's `ErrorResponse` schema.",
    language: "python",
    bad: `# auth.py:67
return {"error": "invalid credentials"}, 401
# auth.py:92
return {"message": "user not found"}, 404
# auth.py:134
return {"detail": "token expired"}, 401`,
    good: `from src.schemas import ErrorResponse

return ErrorResponse(code="invalid_credentials", message="Invalid credentials"), 401
return ErrorResponse(code="user_not_found",     message="User not found"),     404
return ErrorResponse(code="token_expired",      message="Token expired"),      401`,
    status: "open",
  },
  {
    id: "F-009",
    severity: "low",
    rule: "PLR2004",
    title: "Magic number in retry configuration",
    file: "src/payments/retry.py",
    lines: "18",
    description:
      "The retry cap `5` appears in two places without explanation. Promote to a named constant so reviewers can find and tune it.",
    language: "python",
    bad: `def with_retries(fn):
    for attempt in range(5):
        try:
            return fn()
        except TransientError:
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)`,
    good: `MAX_RETRY_ATTEMPTS = 5

def with_retries(fn):
    for attempt in range(MAX_RETRY_ATTEMPTS):
        try:
            return fn()
        except TransientError:
            if attempt == MAX_RETRY_ATTEMPTS - 1:
                raise
            time.sleep(2 ** attempt)`,
    status: "resolved",
  },
  {
    id: "F-010",
    severity: "low",
    rule: "PLR0915",
    title: "checkout() is 142 lines long",
    file: "src/payments/checkout.py",
    lines: "201-342",
    description:
      "The function does cart loading, tax computation, fraud scoring, payment authorization, and order creation in a single body. Extract each phase to a named function so failures point at one step.",
    language: "python",
    bad: `def checkout(cart_id: int, user_id: int) -> Order:
    # 142 lines: cart loading, tax math, fraud check,
    # auth.net call, retry loop, order persistence,
    # email queue, analytics emit, audit log...
    ...`,
    good: `def checkout(cart_id: int, user_id: int) -> Order:
    cart = _load_cart(cart_id, user_id)
    totals = _compute_totals(cart)
    _assert_not_fraudulent(cart, totals)
    auth = _authorize_payment(cart, totals)
    order = _persist_order(cart, totals, auth)
    _emit_post_checkout_events(order)
    return order`,
    status: "wontfix",
  },
  {
    id: "F-011",
    severity: "info",
    rule: "TODO",
    title: "TODO from Q1 2026 still present",
    file: "src/payments/coupons.py",
    lines: "14",
    description:
      "A TODO scoped to Q1 2026 is still in the code as of May. Either resolve it, push the date out with context, or open a tracked issue and remove the comment.",
    language: "python",
    bad: `# TODO(Q1 2026): unify coupon validation between cart and checkout
def validate_coupon(code: str, cart: Cart) -> Coupon:
    ...`,
    good: `# Tracked as PAY-432 — unify coupon validation paths.
def validate_coupon(code: str, cart: Cart) -> Coupon:
    ...`,
    status: "open",
  },
  {
    id: "F-012",
    severity: "info",
    rule: "F401",
    title: "Unused import",
    file: "src/api/utils.py",
    lines: "5",
    description: "`warnings` is imported but never referenced. Removing it speeds up startup imperceptibly and removes a paper-cut for readers.",
    language: "python",
    bad: `import json
import logging
import warnings
from typing import Any`,
    good: `import json
import logging
from typing import Any`,
    status: "resolved",
  },
];
