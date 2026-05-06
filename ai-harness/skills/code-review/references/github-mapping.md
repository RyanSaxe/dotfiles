# GitHub Reviews API Mapping

**When to read this:** when explaining the viewer's Send buttons, debugging `submit.py`, or extending submission.

`tools/submit.py` maps local YAML threads to the GitHub PR Reviews API:

```text
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

It calls this via `gh api -X POST --input -`.

## Field Mapping

- `review.summary` -> `body`
- `review.event` -> `event`
- `target.commit` -> `commit_id`, when available
- `review.threads[]` -> `comments[]`, after filtering out `resolved` and
  `wontfix` threads

Replies are local-only and are not submitted to GitHub.

### Per-Thread Mapping

- `file` -> `path`
- `line` -> `line`
- `start_line` plus `line` -> `start_line` plus `line`
- `body` plus `suggestion` -> `body`; the suggestion is wrapped in a GitHub
  suggestion block
- constant `side: RIGHT`

## Submission Flow

1. Read the YAML.
2. Resolve `<owner>/<repo>` from `gh repo view` or `target.remote`.
3. Build `comments[]` from `review.threads[]`.
4. POST via `gh api repos/{owner}/{repo}/pulls/{pr}/reviews -X POST --input -`.
5. On success, the viewer:
   - Archives the whole review after "Send full review".
   - Removes the sent thread after "Send this thread".
6. On failure, leave the YAML untouched.

## Single-Thread Send

`submit.py --thread-id rev-001` sends exactly one thread. `--comment-id` remains as a deprecated alias for older viewer calls.
