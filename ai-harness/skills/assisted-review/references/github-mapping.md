# GitHub Reviews API Mapping

**When to read this:** when explaining the viewer's Send buttons, debugging `submit.py`, or extending submission.

For full review submission, `tools/submit.py` maps local YAML threads to the
GitHub PR Reviews API:

```text
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

For single-comment submission, it uses GitHub's review comment endpoint:

```text
POST /repos/{owner}/{repo}/pulls/{pull_number}/comments
```

Both paths call GitHub via `gh api -X POST --input -`.

## Field Mapping

- `review.summary.body` -> full-review `body`
- `review.event` -> `event`
- `target.commit` -> `commit_id`, when available
- `review.threads[]` with `type: comment` -> `comments[]`, after filtering
  out `resolved` and `wontfix` threads

Notes, `review.note`, and replies are local-only and are not submitted to GitHub.

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
3. Build `comments[]` from sendable `type: comment` threads.
4. POST via `gh api repos/{owner}/{repo}/pulls/{pr}/reviews -X POST --input -`.
5. On success, the viewer:
   - Removes submitted comment threads and preserves local notes.
   - Archives the whole review only when no threads remain.
   - Removes the sent thread after "Send this thread".
6. On failure, leave the YAML untouched.

## Single-Thread Send

`submit.py --thread-id rev-001` sends exactly one comment thread to
`/pulls/{pr}/comments`. It does not include `review.summary.body`. It refuses
note threads. `--comment-id` remains as a deprecated alias for older viewer
calls.
