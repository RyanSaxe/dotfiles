---
name: code-review
description: Generate a structured code review on a commit or PR. Triggers — "review this code", "code review", "review the PR", "review the diff", "leave comments on", "audit this PR". Produces a YAML review file at ~/.reviews/<repo-slug>/<short-sha>-<utc-timestamp>.review.yaml and auto-launches a long-running local web viewer that lets you triage comments, leave feedback for iteration, and (when a PR is set) submit to GitHub via gh.
license: MIT
---

# code-review

Generate a structured code review on a specific commit (or PR's head commit), persist it as a local YAML file, and open a long-running web viewer for triaging and (optionally) sending comments to GitHub.

## Layout

```text
code-review/
├── SKILL.md             ← this file
├── references/          ← depth docs (read on demand)
│   ├── schema.md        ← annotated YAML schema with examples
│   ├── github-mapping.md ← how YAML → GitHub Reviews API
│   ├── viewer-usage.md  ← daemon lifecycle, --stop, URL routing
│   └── iteration.md     ← the feedback / re-run loop, worked examples
├── examples/            ← populated YAML samples
│   ├── sample.review.yaml          ← fully populated calibration baseline
│   ├── minimal.review.yaml         ← smallest valid file
│   └── iteration-input.review.yaml ← review with feedback fields populated
└── tools/
    ├── view.py          ← self-daemonizing HTTP server (--ensure / --stop / --foreground)
    ├── submit.py        ← posts a review to GitHub via gh api
    ├── validate.py      ← schema check
    └── webapp/          ← static viewer (vanilla JS, no build step)
        ├── index.html
        ├── app.js
        └── style.css
```

The user may provide a target (PR number, "the latest commit", a directory scope). Use what's given; default to HEAD of the current branch.

## Architectural rules

These are inflexible — every other behavior derives from them.

- **Reviews are tied to a specific commit.** `target.commit` is the canonical anchor. Line numbers reference current files at that commit. There is no LEFT/RIGHT diff-side notion.
- **Refuse to run with a dirty working tree.** `git status --porcelain` must be empty. If it isn't: refuse and offer to commit, then re-run.
- **Reviewing a PR means checking out the PR first.** If the user says "review PR #142", run `gh pr checkout 142` before generating.
- **Reviews live at `~/.reviews/<repo-slug>/<short-sha>-<utc-timestamp>.review.yaml`.** `<repo-slug>` is the absolute repo path with `/` replaced by `-`. Never committed; this directory is personal scratch state.
- **Reviews go stale once HEAD moves.** A new `/code-review` against HEAD creates a new review file. Old files stay where they are; the viewer marks them as stale.
- **State clearing is manual** — the viewer has a delete button, or `rm` the file.

## Alignment

Confirm two things only when ambiguous from context:

- **Scope** — recent commit's changes, the whole branch, a specific directory
- **Depth** — quick pass vs. deep audit

One short turn — don't over-ask. Iteration mode auto-detects without asking.

## How to Run

1. **Validate working tree.** `git status --porcelain` must be empty. If not, refuse: _"You have uncommitted changes — line numbers would shift. Want me to commit them first?"_ Then re-run after the commit.
2. **Determine target.** If the user said "review PR #N" → run `gh pr checkout N` first. Read `git rev-parse HEAD` (full SHA), `git rev-parse --abbrev-ref HEAD` (branch), `git rev-parse --show-toplevel` (repo root), and (when a PR is in play) `gh pr view --json number -q .number 2>/dev/null` for the PR number plus `gh repo view --json owner,name -q '.owner.login + "/" + .name' 2>/dev/null` for `owner/repo` (split on `/` into `target.owner` and `target.repo` — both are required whenever `target.pr_number` is set, so the viewer can build a working PR link).
3. **Compute review file path.** `~/.reviews/<repo-slug>/<short-sha>-<utc-timestamp>.review.yaml`. Create the parent directory if needed.
4. **Check for existing review at HEAD's SHA.** If present:
   - With non-empty `review.feedback` or per-comment `feedback` → enter **iteration mode** (read feedback, address it, clear the fields, write the YAML in place). See [`references/iteration.md`](references/iteration.md).
   - Without feedback → ask the user: open the viewer, append more comments, or overwrite from scratch?
5. **Generate the review.** Walk relevant files for the scope. Produce comments per [`references/schema.md`](references/schema.md). Each comment gets a unique `rev-NNN` id (zero-padded), severity (`info | low | medium | high | critical`), category (free text — `correctness`, `security`, `arch`, `perf`, `style`, etc.), markdown body, optional suggestion (raw code, no fences), and `status: open`.
   - Comment bodies are GitHub-flavored Markdown. Do not hard-wrap prose for YAML width; use Markdown structure for intentional breaks.
   - Suggestions are exact GitHub replacement text. Include all leading whitespace; YAML block indentation is not part of the value.
6. **Validate the YAML.** `uv run --script tools/validate.py <path>` — must exit 0. If it fails, fix the YAML and re-validate.
7. **Open the viewer.** `uv run --script tools/view.py --ensure --open --review-path <path>`. Idempotent: if a viewer daemon is already running it just deep-links in the browser; otherwise it daemonizes a fresh one and then opens. See [`references/viewer-usage.md`](references/viewer-usage.md).
8. **Tell the user where it is.** Print the deep-link URL and a one-line summary: `"<short-sha> · <N> comments (<sev breakdown>) · <url>/r/<slug>/<sha-ts>"`.

## Output Contract

**Outcome:** a YAML file at `~/.reviews/<repo-slug>/<short-sha>-<utc-timestamp>.review.yaml`.

**Shape / schema:** top-level keys `version`, `generated_at`, `generated_by`, `target`, `review`. Full schema in [`references/schema.md`](references/schema.md).

**Verification:**

- `uv run --script tools/validate.py <path>` exits 0
- `uv run --script tools/view.py --ensure --open --review-path <path>` returns; the deep-link URL renders the review
- `uv run --script tools/view.py --stop` cleanly shuts down the daemon

## References

- [`references/schema.md`](references/schema.md) — read when generating or editing a review YAML
- [`references/github-mapping.md`](references/github-mapping.md) — read when explaining what `submit.py` does or when debugging a failed send
- [`references/viewer-usage.md`](references/viewer-usage.md) — read when troubleshooting the viewer daemon or routing
- [`references/iteration.md`](references/iteration.md) — read when entering iteration mode (existing YAML, populated feedback)
- [`examples/`](examples/) — three populated YAML samples; the fully-populated `sample.review.yaml` is the calibration baseline for voice and density
