# GitHub Reviews API Mapping

**When to read this:** when explaining what the viewer's "Send" buttons do, when debugging a failed `submit.py`, or when extending the submitter.

`tools/submit.py` maps the YAML to the GitHub PR Reviews API endpoint:

```text
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

It calls this via `gh api -X POST --input -` (reads JSON from stdin).

## Field mapping

| YAML field                   | API field    | Notes                                                  |
| ---------------------------- | ------------ | ------------------------------------------------------ |
| `review.summary`             | `body`       | Top-level review body.                                 |
| `review.event`               | `event`      | `COMMENT`, `REQUEST_CHANGES`, `APPROVE`, or `PENDING`. |
| `target.commit`              | `commit_id`  | Pins the review to a specific SHA.                     |
| `review.comments[]` filtered | `comments[]` | See per-comment mapping below.                         |

Comments with `status: resolved` or `status: wontfix` are **filtered out** before sending. `open` and `acknowledged` are sent.

### Per-comment mapping

| YAML field            | API field             | Notes                                                                                                           |
| --------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------- |
| `file`                | `path`                | Path relative to repo root.                                                                                     |
| `line` (single)       | `line`                | When `start_line` is absent.                                                                                    |
| `start_line` + `line` | `start_line` + `line` | When ranged; both are inclusive endpoints.                                                                      |
| `body` + `suggestion` | `body`                | Body is rendered as `"<body>\n\n```suggestion\n<code>\n```"` when `suggestion` is set; just `<body>` otherwise. |
| (constant)            | `side`                | Always `"RIGHT"` — we never review the diff-LEFT side.                                                          |

## Submission flow

1. Read the YAML, parse with PyYAML.
2. Resolve `<owner>` and `<repo>` from `target.remote` (parsing the git remote URL) or via `gh repo view --json owner,name -q '.owner.login + "/" + .name'`.
3. Build the `comments[]` array, filtering out `resolved` and `wontfix` entries.
4. POST via `gh api repos/{owner}/{repo}/pulls/{pr}/reviews -X POST --input -`.
5. On success, the viewer:
   - For "Send full review": archives the review file (moves to `~/.reviews/.archive/`)
   - For "Send this comment": removes that single comment from the local YAML
6. On failure, print the API error verbatim and leave the file untouched. The user can leave feedback explaining what went wrong and re-iterate.

## Single-comment send

Same flow, but the `comments[]` array has exactly one entry. After a 200/201 response, the submitter rewrites the YAML with that comment removed.

## Worked example

Review YAML:

```yaml
target:
  pr_number: 142
  commit: a3f2c1d8e9b0c4f5a6d7e8f9
review:
  event: COMMENT
  summary: |
    Two issues — see inline.
  comments:
    - id: rev-001
      file: src/auth/session.py
      line: 42
      severity: high
      category: security
      body: |
        SQL injection via string concatenation.
      suggestion: |
        cursor.execute("SELECT ... WHERE user_id = ?", (user_id,))
      status: open
    - id: rev-002
      file: src/auth/middleware.py
      start_line: 15
      line: 22
      severity: medium
      category: arch
      body: |
        Auth runs after rate-limiter. DoS vector.
      status: wontfix # ← will be filtered out
```

Resulting POST payload (after filtering and wrapping):

````json
{
  "commit_id": "a3f2c1d8e9b0c4f5a6d7e8f9",
  "event": "COMMENT",
  "body": "Two issues — see inline.\n",
  "comments": [
    {
      "path": "src/auth/session.py",
      "line": 42,
      "side": "RIGHT",
      "body": "SQL injection via string concatenation.\n\n```suggestion\ncursor.execute(\"SELECT ... WHERE user_id = ?\", (user_id,))\n```"
    }
  ]
}
````

Note `rev-002` is absent (status `wontfix`) and rev-001's suggestion has been wrapped in a fenced block.
