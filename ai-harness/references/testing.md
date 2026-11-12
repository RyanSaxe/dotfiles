# Testing

Tests should explain and protect behavior that matters. Their value is the
confidence they provide, not their count or coverage score.

## Choose the boundary

Start with the contract that could fail from the user's perspective. Test at
the smallest boundary that can prove that contract without replacing the real
behavior with mocks.

- Use unit tests for self-contained decisions and transformations.
- Use integration tests for boundaries between components, tools, or services.
- Use end-to-end tests only for critical journeys that require the assembled
  system.

Prefer a stronger test at the right boundary over the same assertion repeated
at every layer.

## Choose the cases

Use the smallest set of cases that distinguishes the intended behavior from
plausible mistakes. Usually this includes the normal path, meaningful
boundaries, and failures that change what the caller observes. Add a regression
case when a defect reveals a gap in the existing suite.

Do not add tests merely because a file changed. Configuration, documentation,
and mechanical refactors may be better verified directly.

## Keep tests durable

- Assert observable results and stable contracts, not private call sequences or
  incidental representation.
- Avoid mocks and monkeypatching when the real dependency is practical. When a
  substitute is necessary, place it at an owned boundary and preserve the real
  contract.
- Do not freeze wording, formatting, timestamps, or generated output unless
  that exact value is part of the product contract.
- Make test names describe the behavior and condition. A failure should tell a
  reviewer what stopped working.
- Keep setup proportional to the behavior under test. Large fixtures often hide
  a boundary that should be tested more directly.

Run the narrowest relevant test while developing, then the repository's normal
quality gates before handoff. Review the test as documentation: a reasonable
refactor that preserves behavior should usually leave it unchanged.
