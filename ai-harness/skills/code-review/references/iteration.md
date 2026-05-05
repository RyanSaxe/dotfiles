# Iteration Loop

**When to read this:** when re-entering an existing review (the YAML for HEAD's SHA already exists in `~/.reviews/`).

The iteration loop is what makes `/code-review` uniquely valuable beyond a one-shot review:

1. AI generates a review →
2. Human reads it in the viewer, leaves feedback in the input fields →
3. Human re-runs `/code-review` →
4. AI reads the feedback, addresses each item, clears the fields, writes the YAML in place

The same SHA gets the same file path, so iterations build on each other rather than producing N stale review files.

## When to iterate vs. when to overwrite

`/code-review` decides based on tree state × existing-file × feedback-state:

| Working tree | Existing review for HEAD's SHA | Feedback fields | Action                                                                          |
| ------------ | ------------------------------ | --------------- | ------------------------------------------------------------------------------- |
| Dirty        | —                              | —               | **Refuse**; offer to commit, then re-run.                                       |
| Clean        | None                           | —               | Generate fresh review against HEAD.                                             |
| Clean        | Yes                            | Non-empty       | **Iterate**: read feedback, address, clear fields, write in place.              |
| Clean        | Yes                            | All empty       | **Ask** the user: open viewer, append more comments, or overwrite from scratch? |

## Iteration mechanics

When iterating:

1. **Read the existing YAML** with `ruamel.yaml` (round-trip mode preserves formatting).
2. **Read `review.feedback`** (review-level) and each comment's `feedback` (per-comment).
3. **Address each piece of feedback in turn.** This means:
   - Modify the comment's body, suggestion, severity, or category if the feedback says it's wrong/miscalibrated.
   - Delete the comment if the feedback says it's flat-out incorrect.
   - Add new findings if the review-level feedback says you missed something.
   - Recalibrate severities globally if the review-level feedback complains about calibration.
4. **Clear the addressed feedback fields.** Set to empty string or remove. The presence of feedback is the iteration trigger; once addressed, it shouldn't re-trigger.
5. **Write the updated YAML in place.** Same path. The viewer auto-refreshes.

There is **no audit trail in the file**. The conversation explains what changed; the file just reflects the current state. Don't add `iteration_count`, `iterations[]`, or a changelog — that's overengineering local scratch state.

## Worked example: review-level feedback only

Existing YAML at `~/.reviews/myapp/.../d598ced-....review.yaml`:

```yaml
review:
  feedback: |
    Severity calibration is too soft across the board. We hit the TOCTOU
    bug last quarter and it caused a real outage — that should be critical,
    not high. Also: please look at notify.sh's emit_bell — I think there's a
    similar fall-through bug.
  comments:
    - id: rev-001
      severity: high          # ← will become critical
      ...
    # (no rev-004 yet — will be added)
```

Iteration response:

1. Re-read `attention-daemon.sh` — confirm rev-001 represents a production-impact bug. Bump severity to `critical`. Update the body to lead with the user-visible failure.
2. Read `notify.sh`. Look for the fall-through pattern in `emit_bell`. Find it, draft a new comment as `rev-004`, append.
3. Re-calibrate other comments if the same calibration logic applies.
4. Clear `review.feedback`.
5. Write the YAML.

Updated:

```yaml
review:
  feedback: ""              # ← cleared
  comments:
    - id: rev-001
      severity: critical    # ← bumped
      body: |
        Production outage path: duplicate notifications when daemons race on startup
        — we hit this in Q1 2026. ...
    - id: rev-004           # ← new
      file: ai-harness/scripts/notify.sh
      ...
```

## Worked example: per-comment feedback only

Existing YAML:

```yaml
comments:
  - id: rev-003
    file: ai-harness/scripts/agent-utils.sh
    severity: low
    body: |
      The agent-name match mixes a case-sensitive `comm == "claude"`...
    feedback: |
      Low priority — on macOS/Linux the `comm` field is always lowercase
      for these binaries in practice. Drop this comment.
```

Iteration response:

1. Read the feedback on `rev-003`. User says drop.
2. Remove `rev-003` from `comments[]`. (Don't keep it with status `wontfix` — the user said drop, not "I disagree.")
3. Renumber remaining `rev-NNN` ids to stay contiguous? **No** — IDs are stable. `rev-002`, `rev-004`, etc. is fine. Gaps are intentional and don't break anything.
4. Write the YAML.

If the feedback had been _"keep it but downgrade to info,"_ the response would be:

1. Set `severity: info`.
2. Clear `feedback`.
3. Write.

## Worked example: both populated

Treat each piece independently. Process review-level feedback first (may add/remove/recalibrate comments). Then process each per-comment feedback.

## What not to do

- **Don't ask the user before iterating** when feedback is populated. The presence of feedback is the explicit invitation.
- **Don't preserve old feedback "for context."** Once addressed, clear it. The conversation in the chat is where context lives.
- **Don't open the viewer before applying feedback.** Apply, write, validate, _then_ `--ensure --open`.
- **Don't change comment IDs.** They're the user's stable handles for follow-up feedback.
