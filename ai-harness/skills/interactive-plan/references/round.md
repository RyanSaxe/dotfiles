# One round

Interactive planning is a loop, and its value comes from the reviewer's
feedback. The sooner a revision reaches the reviewer, the sooner the plan
gets better, so work well and quickly: put every open point on the pages,
publish, and let the feedback do the refining. Ship polished, not perfect.
A page with unpleasant components or careless writing distracts the
reviewer from the decision, and a page that arrives late delays every
decision after it. The build checks each page's structure, and the
reviewer's browser shows the result. Looking at a page yourself is for the
rare page that carries something you built and cannot judge from its
source; then publish.

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
   source, before the pages. Mark a step started before you write it and
   done after, and say what you start next in the same command:
   `progress --done "Update Agreed" --start "Page title"`, with several
   titles split on `|` when they run together. A batch of reports before
   publish tells the reviewer nothing. Pages can be in progress together
   and finish in any order, and independent pages can go to subagents.
   Author under a directory of your own in the system temp directory,
   starting from the copy of the last revision's source that `read`
   reports as `status.current.source`. Every
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
6. Publish. Run `publish --file ARTIFACT.html --source DIR` under a new
   revision id, say in the chat what changed, and stop. The copy of `DIR`
   kept with the revision is where the next round starts. The hub wakes you for the next
   round.

When the user tells you in the chat to stop the review, run `pause`
instead of publishing. A submission is feedback, never an instruction to
stop.
