# Iteration Loop

**When to read this:** when re-entering an existing review with user-authored threads or user replies.

The iteration loop is local and discussion-based:

1. AI generates review threads.
2. Human reads them in the viewer, starts threads, edits the overview, or adds replies.
3. Human re-runs `/assisted-review`.
4. AI reads the overview and thread discussion, updates the YAML, and appends AI replies when useful.

The viewer does not call AI. It only edits YAML, refreshes files, and submits selected PR comments. Local notes remain in the review file.

## When To Iterate

Iterate when either condition is true:

- `review.summary`, `review.note`, or a thread has latest reply from `user`.
- A thread has `author: user` and no later AI reply.

Otherwise ask whether to open the viewer, append a new pass, or regenerate from scratch.

## Iteration Mechanics

1. Read the existing YAML with `ruamel.yaml` when possible so formatting is preserved.
2. Read `review.summary`, `review.note`, each thread's body, replies, `anchor_text`, and current source location.
3. Address user-authored discussion:
   - Edit the thread body, severity, confidence, category, suggestion, or status.
   - Append an `ai` reply when responding to a user reply matters for future context.
   - Delete a thread only when the user clearly asked to drop it.
   - Add new threads if the user asked for another area to be reviewed.
   - Keep `type: comment` for GitHub-sendable findings and `type: note` for local-only reviewer aids.
4. Manually move threads when needed. The deterministic refresh only handles exact obvious moves; the AI may use the code context to update `file`, `line`, `start_line`, `anchor_text`, and `anchor_status`.
5. Validate, then open the viewer.

Do not add a separate audit log. The overview blocks, thread bodies, and `replies[]` are the local conversation.

## Worked Example

Existing thread:

```yaml
threads:
  - id: rev-003
    type: comment
    author: ai
    file: scripts/notify.sh
    line: 44
    severity: medium
    confidence: low
    category: correctness
    body: |-
      This may double-send when the lock recovery path races.
    status: open
    anchor_text: |-
      recover_lock || send_notification
    anchor_status: current
    replies:
      - author: user
        body: |-
          This is real, but the impact is higher. It caused a production duplicate last month.
```

Iteration response:

1. Re-read `scripts/notify.sh`.
2. Confirm the duplicate-send path.
3. Update severity/confidence and body.
4. Append an AI reply.

Updated:

```yaml
threads:
  - id: rev-003
    type: comment
    severity: high
    confidence: high
    body: |-
      Duplicate notification path: if lock recovery races, both processes can send the same notification. Since this already caused a production duplicate, treat this as a real correctness bug rather than a speculative race.
    replies:
      - author: user
        body: |-
          This is real, but the impact is higher. It caused a production duplicate last month.
      - author: ai
        body: |-
          Confirmed. I raised the severity and rewrote the finding around the duplicate-send impact.
```

## What Not To Do

- Do not wait for a clean worktree before reviewing local state.
- Do not clear user replies after addressing them.
- Do not preserve obsolete locations when the current code makes the right location clear.
- Do not change thread IDs.
- Do not submit local replies to GitHub.
