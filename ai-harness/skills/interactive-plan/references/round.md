# Run one review round

The hub wakes the agent after the reviewer submits a complete revision. Run
`node scripts/session.mjs read --session-dir PATH` and read the submission and
new chat feedback. An acceptance follows [session.md](session.md); do not
publish another revision after acceptance.

For feedback, decide which points are settled, reopened, retired, or still
open. A recommendation is not an agreement. The Agreed page records each
settled decision and its source. Read [agreements.md](agreements.md) before
changing it.

1. Write this revision's Agreed source first. Build it with
   `node scripts/build.mjs agreed.json agreed.html`, then run
   `node scripts/session.mjs publish --session-dir PATH --file agreed.html --source DIR`.
   The publisher resolves its source references before the reader can see it.
2. Choose the pages this revision needs. Make `pages.json` contain an ordered
   `pages` array of `{ "id": "topic", "title": "Topic" }` entries. Run
   `progress --pages pages.json` after Agreed. A final plan lists `overview`
   first. Do not copy a previous page just to fill the new revision. A topic
   moved to Agreed may disappear, and a new topic may get a new page ID.
3. Report work with `progress --start ID`. Several declared pages can be
   active together. Put every remaining open point on a page next to the
   proposal it affects, and ask every question in the browser, not in chat.
4. Build each page with `build.mjs PAGE.json PAGE.html`. Run the same
   `publish --file PAGE.html --source DIR` command. A successful publication
   makes that page readable and marks it done. It cannot be replaced in this
   revision. Pages may finish in any order.
5. The last listed page completes the revision and enables Submit. Tell the
   reviewer what changed, then stop. The next round starts after feedback.

Build is the required publication check. It rejects structural problems and
writes no output on failure. Read each page against [quality.md](quality.md)
and [writing.md](writing.md). Inspect a browser preview when the authored
content needs visual judgment. Do not put a browser launch or screenshot
check on every publication.
