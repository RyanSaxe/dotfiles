---
name: visual-review
description: Explore and explain a codebase visually in a browser session mounted on the repository. Use only when the user explicitly invokes visual-review by name, never for ordinary questions about code.
---

# Visual review

Answer questions about a repository with an organized, visual explanation the
user reads in a browser while the real code sits beside it.

You start a local helper mounted on the repository and open a browser app. The
user asks; you plan an outline of pages, then write each page as Markdown with
diagrams, excerpts of the real lines, diffs, and notes. Pages appear as you
write them. The user follows references into the files, selects lines, and asks
again from where they are looking. The session exports to one HTML file.

This skill is invoked by name. It is not a review tool and posts nothing to
GitHub.

## The loop

1. Start the helper from inside the repository, open its URL in the user's
   browser, and give them the link.
2. Wait. The helper hands you one question at a time.
3. For each question: read the repository, send `plan` with the page titles so
   the outline appears at once, then write the pages in order, keeping a
   `status` line current. Mark only that question `done`.
4. Immediately resume the listener after every page, status update, `done`
   command, timeout, follow-up, and side question.

## Session lifecycle

Once the helper starts, the session is an open conversation. `done` marks one
question complete; it does not end the session.

Use this loop until the user explicitly says `stop`, `pause`, `cancel`,
`finished`, or redirects away from the visual review:

```text
listen:
  event = wait --timeout 55
  if event is a timeout:
    go to listen
  acknowledge the event
  answer or extend the session
  go to listen
```

Never send a final-channel response while the session is open. Use commentary
for progress and side questions so the same turn can return to `wait`.

If the user sends a message while the session is open:

- Treat a follow-up as another event for the same session.
- Answer a side question in commentary, then resume `wait`.
- Preserve the existing session directory and question id.
- Only stop polling when the user explicitly ends, pauses, cancels, or
  redirects the review.

If a tool call or conversation turn is interrupted, the next turn must resume
the same session before doing anything else. Read `state`, retrieve the next
unread event, acknowledge only events that were read, and return to the loop.
Do not start a replacement session.

A `wait` timeout is never completion. A helper fetch error is never completion:
check whether the helper process is alive, retry the same session, and inspect
the recorded owner before using `--recover-lock`. Never delete ownership files
blindly.

After `done`, export only if useful, then immediately call `wait` again. Do not
return a final response merely because all currently planned pages are written.

Read each reference before the step it covers:

- [session.md](references/session.md) before starting or resuming a session.
- [protocol.md](references/protocol.md) before answering: the commands and the
  events.
- [answering.md](references/answering.md) before writing the first page. It is
  the standard the pages are judged by: show the visual, then say the fewest
  sentences that make it mean something, and leave out anything that does not
  help the reader understand faster.
- [blocks.md](references/blocks.md) for the block grammar, with one worked
  example of each and a line on when it earns its place.
- [setup.md](references/setup.md) on first use in an environment, or when
  something fails to start.

## Rules

- Confirm every path, symbol, and line before you name it. A citation from
  memory is a bug the reader will find.
- The repository is read-only. The helper serves committed content and never
  writes, except one ref under `refs/visual-review/` when a pull request is
  named. Uncommitted work is invisible; say so if it matters.
- Write page files under the session directory's `drafts/` or your own
  scratch space; nothing into the repository.
- Never end your turn while the session is live. A `wait` timeout, `done`,
  export, empty queue, or written outline is not completion. Resume `wait`.
  Stop only after the user explicitly says so, pauses, cancels, or redirects.
- Do not post anything anywhere. This skill explains; it does not review.
