# One round

A round begins when the hub wakes you with a submission and ends when you
publish the next revision and stop. The wake message names `read`; running
it returned the submission with its choices, notes and answers and marked
it read. Every session command is
`node scripts/session.mjs COMMAND --session-dir PATH`, with the path from
the wake message.

1. Read. Read the whole submission, and anything the user said in the chat
   since the last revision. [quality.md](quality.md) says what makes pages
   and plans good; read it before the first revision and again when you do
   not remember it. The contracts are [artifact.md](artifact.md),
   [agreements.md](agreements.md), [frame.md](frame.md),
   [prototypes.md](prototypes.md) and the
   [component index](../components/index.md); look one up when a page
   needs it instead of re-reading them.
2. Agreed. Decide what the feedback did to each open point: settled,
   reopened, retired, or still open. A recommendation is not an agreement,
   and an answer is recorded once.
3. Steps. Declare one step for Agreed and one per page you will add or
   change: `progress --steps "Update Agreed|Page title|Page title"`. The
   card adds reading, checking and publishing on its own; do not declare
   them.
4. Work. Update Agreed comes first: write the agreements, each with its
   source, before the pages. Run `progress --start "Title"` before you
   write a step's file and `progress --done "Title"` after, each as its own
   command at the moment it happens; a batch of reports before publish
   tells the reviewer nothing. Pages can be in progress together and
   finish in any order, and independent pages can go to subagents. Every
   open point that remains goes on the pages of this revision, one page
   per topic. Anything the next revision needs from the user is asked on a
   page, next to the proposal it affects, never in the chat. A settled
   point loses its control.
5. Check. Build with `node scripts/build.mjs SOURCE.json OUT.html`. It
   prints the output path when it finds nothing and otherwise lists every
   structural problem and writes nothing; fix them and build again. Read
   every page against [quality.md](quality.md) and every sentence you
   wrote against [writing.md](writing.md). Nothing else is required before
   publishing.
6. Publish. Run `publish --file ARTIFACT.html` under a new revision id,
   say in the chat what changed, and stop. The hub wakes you for the next
   round.

When the user tells you in the chat to stop the review, run `pause`
instead of publishing. A submission is feedback, never an instruction to
stop.
