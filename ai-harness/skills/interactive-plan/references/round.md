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

The hub wakes the agent when the reviewer submits. Every command is
`node scripts/session.mjs COMMAND --session-dir PATH`, with the path from the
wake message.

## Read the feedback

Run `read`. It returns the submission and marks it read. Also read anything
the user said in the chat since the last revision. An acceptance follows
[session.md](session.md), and no pages are published after it.

- `groups.alignUnflagged: true` means the reviewer agrees with every decision
  on the revision that no note, choice or answer challenges. A submission may
  contain nothing else. When the field is `false` or missing, silence is not
  agreement.
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
   `node scripts/build.mjs agreed.json agreed.html`, then
   `publish --file agreed.html --pages pages.json --source DIR`. The reader
   sees Agreed and every page name at once.
3. Mark a page started as soon as work on it begins, research included:
   `progress --start ID`, or `--start "a|b"` for pages worked on at the same
   time. Independent pages can be worked on in parallel, by subagents where
   the harness has them. To revise an earlier page, copy its source from the
   session's `src/<revision>/<page-id>/`.
4. Publish each page as soon as it builds:
   `node scripts/build.mjs PAGE.json PAGE.html`, then
   `publish --file PAGE.html --source DIR`. Publishing marks the page ready.
   Do not hold finished pages back for one publish at the end.
5. The last page completes the revision and enables Submit. Say in the chat
   what changed, then stop.

A published page cannot change in this revision. Build is the publication
check: it lists every structural problem and writes nothing on failure.
Read each page against [quality.md](quality.md) and
[writing.md](writing.md) before publishing it. Open a page in a browser only
when it has CSS or a script you wrote and cannot judge from the source.
