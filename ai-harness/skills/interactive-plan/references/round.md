# Run one review round

Every round has the same goals. The reviewer should be reading within
minutes and never reading something half done. Publish Agreed and the page
names first, then each page once it is complete, so a thorough revision
still starts quickly. Research what this revision's pages need, not
everything the final plan will. Give the reviewer a revision they can work
through in one sitting, and show each subject with the visual that lets
them judge it. The final plan must stand on its own for someone who saw
none of the revisions. [quality.md](quality.md) has the detail behind these
goals. Reread it when a page or the plan needs more than this paragraph.

The hub wakes the agent when the reviewer submits, and the wake message
names `ack`. Every command is
`node scripts/session.mjs COMMAND --session-dir PATH`, with the path from the
wake message, and every command prints the next step.

## Tell the reviewer what you are doing

Run `ack` first when the hub wakes you. It tells the reviewer you have their
submission, without reading it, and prints where to go next.

From the first revision on, `ack --note "…"` is how the reviewer knows what
you are working on: the note appears on their Feedback card beside the time
you sent it. Run it whenever you start something they would want to know
about, such as reading their feedback, checking the code a page depends on,
planning the pages, writing a page or waiting for subagents. Write the note
for them, in under 80 characters. `progress --start` shows which page you
are on, and a note says what you are doing on it:
`ack --note "Adding last month's CI failures to the retry page"`.

Report whenever the work changes, and at least every five minutes. After
five minutes without a report, the card's report line and the Pages heading
turn orange. `read`, `progress` and `publish` are reports too, and each
clears the last note. A subagent that writes a page reports with `progress`
and `ack` itself.

## Read the feedback

Run `read`. It returns the submission as `event.payload` and marks it read.
Its `intent` is `feedback-only` for feedback and `accept-plan` for an
acceptance, and its `groups` hold the choices, answers and notes. Also read
anything the user said in the chat since the last revision. An acceptance
follows [session.md](session.md), and no pages are published after it.

- `groups.alignUnflagged: true` means the reviewer agrees with what the
  pages stated that no note challenges: a proposed design, wording or plan.
  It answers no control. A choice with nothing selected stays open, even when
  an option was recommended, and a checklist is exactly the boxes the
  reviewer left checked, which can be none. A submission may contain nothing
  but this. When the field is `false` or missing, silence is not agreement.
- A note's anchor does not limit its reach. Read each note for every decision
  it challenges.
- Open the image at every `attachments` path on a note, and the
  `previewPath` PNG of a drawing answer. `scenePath` holds the drawing's
  editable shapes.

Update the task first, because feedback can change what is being built.
Then decide what the feedback did to each decision: settled, reopened,
retired or still open. A recommendation is not an agreement. Read
[agreements.md](agreements.md) before changing Agreed.

## Publish the revision

1. Plan the revision: the decisions that matter most now, in coherent pages
   the reviewer can work through in one sitting, the most consequential
   first. Write the pages that follow Agreed to `pages.json` as
   `{ "pages": [{ "id": "topic", "title": "Topic" }] }`. A settled topic
   leaves the list, and an unchanged page is not repeated. A final plan
   follows the final plan section of quality.md and lists `overview` first.
2. Build Agreed and publish it with the list before writing any other page:
   `node scripts/build.mjs SRC/agreed/agreed.json OUT/agreed.html`, then
   `publish --file OUT/agreed.html --pages pages.json --source SRC/agreed`.
   [artifact.md](artifact.md) describes the source directories. The reader
   sees Agreed and every page name at once.
3. Mark a page started as soon as work on it begins, research included:
   `progress --start ID`, or `--start "a|b"` for pages worked on at the same
   time. Independent pages can be worked on in parallel, by subagents where
   the harness has them. To revise an earlier page, copy its source from the
   session's `src/<revision>/<page-id>/` and change its `revision` to this
   one.
4. Publish each page as soon as it builds:
   `node scripts/build.mjs SRC/ID/ID.json OUT/ID.html`, then
   `publish --file OUT/ID.html --source SRC/ID`. Publishing marks the page
   ready.
   Do not hold finished pages back for one publish at the end.
5. The last page completes the revision and enables Submit. Say in the chat
   what changed, then stop.

A published page cannot change in this revision. Build is the publication
check: it lists every structural problem and writes nothing on failure.
Read each page against [quality.md](quality.md) and
[writing.md](writing.md) before publishing it. Open a page in a browser only
when it has CSS or a script you wrote and cannot judge from the source.
