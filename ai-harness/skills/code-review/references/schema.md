# Review YAML Schema

**When to read this:** when generating, editing, or validating a review YAML file.

## File location

`~/.reviews/<repo-slug>/<short-sha>-<utc-timestamp>.review.yaml`

- `<repo-slug>` is the absolute path of the repo with `/` replaced by `-`. Example: `/Users/ryansaxe/projects/myapp` → `Users-ryansaxe-projects-myapp`.
- `<short-sha>` is the first 7 chars of the target commit SHA.
- `<utc-timestamp>` is `YYYYMMDDTHHMMSSZ` — UTC, no separators. Multiple reviews on the same commit get distinct timestamps.

The directory is created lazily on the first review for a given repo. Reviews are never committed; this is personal scratch state.

## Top-level structure

```yaml
version: 1
generated_at: 2026-05-05T09:12:00Z
generated_by: claude-opus-4-7 # informational; helps trace provenance

target:
  repo_root: /Users/me/projects/myapp # absolute path at generation time
  commit: a3f2c1d8e9b0c4f5a6d7e8f9 # full SHA — the canonical anchor
  branch: feature/auth-refactor # optional
  pr_number: 142 # optional; presence enables direct submit
  owner: my-org # required when pr_number is set; powers the topbar PR link
  repo: myapp # required when pr_number is set; powers the topbar PR link
  remote: origin # optional; fallback for resolving owner/repo when not set

review:
  event: COMMENT # COMMENT | REQUEST_CHANGES | APPROVE | PENDING
  summary: |
    Two-to-five-sentence prose summary of what was reviewed and the headline
    findings. Visible at the top of the per-review view in the viewer.

  feedback: | # free-form notes from the human; addressed on next /code-review
    Optional. Empty / missing = nothing to address.

  comments:
    - id: rev-001
      file: src/auth/session.py
      line: 42 # single-line comment
      severity: high # info | low | medium | high | critical
      category: security # free-form: correctness, security, arch, perf, style, docs, test, naming, ...
      body: |
        Markdown. Renders in the viewer and (when sent) on GitHub.
      suggestion: | # optional; raw code (no fences). Submitter wraps it.
        cursor.execute(
            "SELECT * FROM sessions WHERE user_id = ?",
            (user_id,),
        )
      status: open # open | acknowledged | resolved | wontfix
      feedback: | # optional per-comment feedback for next /code-review
        Wrong — we use SQLAlchemy here, this isn't a raw query.
```

## Field rules

### `id`

Unique within the file. Format `rev-NNN` zero-padded to three digits. IDs are stable across iterations — they're the user's handle for referencing comments in feedback (_"drop rev-002"_).

### Line targeting

Always references files **at `target.commit`**, on the present-state side (no diff LEFT/RIGHT).

- **Single-line:** `line: <N>`
- **Range:** `start_line: <N>` plus `line: <M>` where `line` is the inclusive end. Mirrors the GitHub Reviews API.

### `severity`

Five-rung enum: `info | low | medium | high | critical`. Calibration:

| Rung       | Meaning                                                       | Example                                             |
| ---------- | ------------------------------------------------------------- | --------------------------------------------------- |
| `critical` | Will hurt you. Data loss, security exploit, prod outage path. | SQL injection, secret committed in plaintext.       |
| `high`     | Real bug or significant design flaw. Worth fixing soon.       | TOCTOU race, host-specific path in shared dotfiles. |
| `medium`   | Worth addressing, not urgent.                                 | Hardcoded relative path, fragile parser.            |
| `low`      | Minor correctness or style.                                   | Inconsistent comparison, unused variable.           |
| `info`     | FYI. No action expected.                                      | "Consider this convention next time."               |

Use the high end sparingly; if every comment is `high` the rung loses meaning.

### `category`

Free text. Common values: `correctness`, `security`, `arch`, `perf`, `style`, `docs`, `test`, `naming`. Don't enumerate; let it grow.

### `body`

Markdown. The viewer renders inline-code (backticks), bold, paragraph breaks. Lead with the _what_ and _why_; if the fix is non-obvious, end with a sentence on the _how_.

### `suggestion`

Optional. **Raw code, no fences.** The submitter wraps it in ` ```suggestion\n…\n``` ` when posting to GitHub. The viewer renders it as a unified diff against the original line(s) at `start_line..line`.

### `status`

Lifecycle starts at `open`. Human flips to one of:

- `open` — default; will be sent on submit
- `acknowledged` — valid finding, send to PR author for them to address (sent)
- `resolved` — I'll fix this myself locally, no need to bother PR author (skipped on submit)
- `wontfix` — disagree with the AI on this (skipped on submit)

### `event` (top-level)

Controls the GitHub submission type when sent:

- `COMMENT` — the default; non-blocking comments
- `REQUEST_CHANGES` — blocks PR merge until addressed
- `APPROVE` — green checkmark
- `PENDING` — draft, doesn't send to PR author yet

### `review.feedback` and per-comment `feedback`

Optional. Inputs for the iteration loop. If non-empty, the next `/code-review` reads them, addresses each, and clears the field. See [`iteration.md`](iteration.md).

## Examples

- [`examples/sample.review.yaml`](../examples/sample.review.yaml) — fully populated: 9 comments across 6 files, varied severity, one with a multi-line suggestion, one with a ranged anchor, one with populated feedback.
- [`examples/minimal.review.yaml`](../examples/minimal.review.yaml) — one comment, no suggestion, no PR. Smallest valid file.
- [`examples/iteration-input.review.yaml`](../examples/iteration-input.review.yaml) — review with both review-level and per-comment feedback populated. Documents what the AI reads on the next `/code-review`.
