---
name: code-review
description: Generate a structured code review on local code or a PR. Triggers — "review this code", "code review", "review the PR", "review the diff", "leave comments on", "audit this PR". Produces a YAML review file at ~/.reviews/<repo-slug>/<ref>-<utc-timestamp>.review.yaml and auto-launches a local web viewer for triaging threads, local replies, refresh, and optional GitHub submission.
license: MIT
---

# code-review

Generate a structured review, persist it as a local YAML file, and open the web viewer for triaging threads. The review can target the current local folder state, including uncommitted changes, or the current checkout of a PR.

## Layout

```text
code-review/
├── SKILL.md
├── references/
│   ├── schema.md
│   ├── github-mapping.md
│   ├── viewer-usage.md
│   └── iteration.md
├── examples/
│   ├── sample.review.yaml
│   ├── minimal.review.yaml
│   └── iteration-input.review.yaml
└── tools/
    ├── view.py
    ├── submit.py
    ├── validate.py
    └── webapp/
```

The user may provide a target: a PR number, recent changes, the whole branch, a directory, or the current local state. Default to the current local folder state.

## Architectural Rules

- **Reviews are local thread files.** `review.threads[]` is the canonical list. Threads may be started by `ai` or `user`; replies are local context for future terminal-driven AI iteration.
- **Local reviews may be dirty.** Do not refuse because the worktree has staged, unstaged, or untracked changes. Review the current folder state the user asked about.
- **PR reviews use the current PR checkout.** If the user says "review PR #142", run `gh pr checkout 142` first so the local folder reflects the PR before generating the review.
- **The viewer refresh is deterministic.** It reloads files and moves anchors only when the original `anchor_text` appears exactly once. When uncertain, it marks the thread instead of guessing.
- **AI may manually move threads during iteration.** If code changed too much for deterministic refresh, use `anchor_text`, the current source, and the thread discussion to move the thread to the right place or mark it obsolete/resolved.
- **GitHub submission ignores local replies.** Only the thread body and optional suggestion are submitted.
- **Reviews live at `~/.reviews/<repo-slug>/<ref>-<utc-timestamp>.review.yaml`.** `<repo-slug>` is the absolute repo path with `/` replaced by `-`. Reviews are personal scratch state and are never committed.

## Alignment

Confirm only when ambiguous from context:

- **Scope** — current local state, recent diff, branch, PR, or directory
- **Depth** — quick pass vs. deep audit

One short turn is enough. Iteration mode is detected from existing thread replies.

## How to Run

1. **Determine target.** If the user said "review PR #N" → run `gh pr checkout N` first. Read `git rev-parse HEAD`, `git rev-parse --abbrev-ref HEAD`, `git rev-parse --show-toplevel`, and PR metadata when available.
2. **Compute review file path.** Use `~/.reviews/<repo-slug>/<ref>-<utc-timestamp>.review.yaml`, where `<ref>` is the short commit SHA when available, otherwise a short fingerprint label.
3. **Check for an existing review for this target.** If an existing review has user replies that the AI has not answered, enter iteration mode. Otherwise ask whether to open it, append more threads, or generate fresh.
4. **Generate the review.** Walk relevant files for the scope. Produce threads per [`references/schema.md`](references/schema.md). Each thread gets a stable `rev-NNN` id, `author: ai`, severity, confidence, category, body, optional suggestion, `status: open`, `anchor_text`, `anchor_status: current`, and `replies: []`.
5. **Anchor exactly.** `anchor_text` is the exact current source text for `start_line..line`. For a single-line thread, it is that one line. This lets deterministic refresh move only obvious anchors.
6. **Validate the YAML.** For a freshly generated review, `uv run --script tools/validate.py --require-current-anchors <path>` must exit 0. This checks both schema shape and exact anchor text against the current source. For an existing review that may have drifted during iteration, use `uv run --script tools/validate.py <path>` for schema-only validation unless you intentionally want strict current-anchor enforcement. If validation fails, fix the YAML and re-validate.
7. **Open the viewer.** `uv run --script tools/view.py --ensure --open --review-path <path>`.
8. **Tell the user where it is.** Print the deep-link URL and a one-line summary: `"<ref> · <N> threads (<sev breakdown>) · <url>/r/<slug>/<key>"`.

## Output Contract

**Outcome:** a YAML file at `~/.reviews/<repo-slug>/<ref>-<utc-timestamp>.review.yaml`.

**Shape / schema:** top-level keys `generated_at`, `generated_by`, `target`, `review`. Full schema in [`references/schema.md`](references/schema.md).

**Verification:**

- Fresh review: `uv run --script tools/validate.py --require-current-anchors <path>` exits 0
- Iterated review with possible code drift: `uv run --script tools/validate.py <path>` exits 0
- `uv run --script tools/view.py --ensure --open --review-path <path>` returns; the deep-link URL renders the review
- `uv run --script tools/view.py --stop` cleanly shuts down the daemon

## References

- [`references/schema.md`](references/schema.md) — read when generating or editing a review YAML
- [`references/github-mapping.md`](references/github-mapping.md) — read when explaining what `submit.py` does or debugging send failures
- [`references/viewer-usage.md`](references/viewer-usage.md) — read when troubleshooting the viewer daemon, routing, or refresh
- [`references/iteration.md`](references/iteration.md) — read when an existing review has user replies to address
- [`examples/`](examples/) — populated YAML samples
