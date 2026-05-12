# Review YAML Schema

**When to read this:** when generating, editing, or validating a review YAML file.

## File Location

`~/.reviews/<repo-slug>/<ref>-<utc-timestamp>.review.yaml`

- `<repo-slug>` is the absolute repo path with `/` replaced by `-`.
- `<ref>` is the short commit SHA when available, otherwise a short fingerprint label.
- `<utc-timestamp>` is `YYYYMMDDTHHMMSSZ`.

## Top-Level Structure

```yaml
generated_at: 2026-05-05T09:12:00Z
generated_by: codex

target:
  kind: local # local | pr
  repo_root: /Users/me/projects/myapp
  branch: feature/auth-refactor
  commit: a3f2c1d8e9b0c4f5a6d7e8f9 # optional but preferred when available
  fingerprint: 46f3c2... # current reviewed folder state, optional but preferred
  base_ref: origin/main # optional; viewer diff context compares current state against this Git ref
  pr_number: 142 # required for PR submission
  owner: my-org # required when pr_number is set
  repo: myapp # required when pr_number is set
  remote: origin # optional fallback for resolving owner/repo

review:
  event: COMMENT # COMMENT | REQUEST_CHANGES | APPROVE | PENDING
  summary: |
    Two-to-five-sentence prose summary of what was reviewed and the headline findings.

  threads:
    - id: rev-001
      author: ai # ai | user
      file: src/auth/session.py
      line: 42
      severity: high # info | low | medium | high | critical
      confidence: medium # low | medium | high
      category: security
      body: |
        Markdown. Renders in the viewer and, if submitted, on GitHub.
      suggestion: |
        cursor.execute(
            "SELECT * FROM sessions WHERE user_id = ?",
            (user_id,),
        )
      status: open # open | acknowledged | resolved | wontfix
      anchor_text: |
        cursor.execute(f"SELECT * FROM sessions WHERE user_id = {user_id}")
      anchor_status: current # current | moved | missing | ambiguous
      replies:
        - author: user
          body: |
            This path actually uses SQLAlchemy; please re-check.
        - author: ai
          body: |
            Agreed. I removed the raw SQL suggestion and downgraded confidence.
```

## Field Rules

### `id`

Unique within the file. Use `rev-NNN`, zero-padded. IDs are stable handles for local discussion and should not change across iterations.

### `author`

Use `ai` for threads or replies written by the reviewing agent. Use `user` for threads or replies created in the viewer by the human.

### Line Targeting

Line numbers reference the current source file for the reviewed local state.

- Single line: `line: <N>`
- Range: `start_line: <N>` plus `line: <M>` where `line` is the inclusive end.

### `anchor_text` and `anchor_status`

`anchor_text` is the exact source text for the reviewed line or range at generation time. For freshly generated reviews, run:

```bash
uv run --script tools/validate.py --require-current-anchors <path>
```

That strict mode verifies that every thread's `anchor_text` exactly matches the current source at `start_line..line`. During later review iteration, code may legitimately drift; use schema-only validation (`uv run --script tools/validate.py <path>`) when stale, moved, or missing anchors are expected and should be handled by the viewer refresh flow.

The viewer refresh uses anchor text conservatively:

- `current` — text still matches at the stored line/range.
- `moved` — text appeared exactly once elsewhere and the viewer moved the line/range.
- `missing` — text was not found.
- `ambiguous` — text appeared multiple times.

If `anchor_status` is `missing` or `ambiguous`, do not submit or edit suggestions until the AI or user moves the thread to the right location.

### `target.base_ref`

Optional Git ref used only by the viewer's live diff context. It may be a branch, remote branch, commit SHA, `HEAD`, or an expression such as `HEAD~2`. The review file stores only this ref string; the viewer computes diff stats and hunks live from `target.repo_root` against the current filesystem state. Do not store generated diff contents in review YAML.

### `severity`

Five-rung enum: `info | low | medium | high | critical`.

Use the high end sparingly; if every thread is high, the rung loses meaning.

### `confidence`

Three-rung enum: `low | medium | high`.

Severity is impact if true. Confidence is how sure the reviewer is. A finding may be high severity but low confidence when it flags a plausible production risk that needs verification.

### `category`

Free text. Common values: `correctness`, `security`, `arch`, `perf`, `style`, `docs`, `test`, `naming`.

### `body`

GitHub-flavored Markdown. Lead with what and why; if the fix is non-obvious, end with how. Do not hard-wrap prose for YAML width.

### `suggestion`

Optional raw exact replacement code, no fences. The submitter wraps it in a GitHub suggestion block when posting. Include every leading tab or space required.

### `status`

- `open` — default; may be sent
- `acknowledged` — valid finding, may be sent
- `resolved` — fixed locally; skipped on submit
- `wontfix` — intentionally not addressed; skipped on submit

### `replies`

Local-only thread discussion. The AI reads user replies on the next terminal `/code-review` run. GitHub submission ignores replies and sends only the thread `body` plus optional `suggestion`.

## Examples

- [`examples/sample.review.yaml`](../examples/sample.review.yaml)
- [`examples/minimal.review.yaml`](../examples/minimal.review.yaml)
- [`examples/iteration-input.review.yaml`](../examples/iteration-input.review.yaml)
