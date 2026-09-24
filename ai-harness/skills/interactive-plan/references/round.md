# Run one review round

Interactive planning is a loop. Send each revision as soon as it contains
new or changed material the reviewer needs. Use the reviewer's feedback to
refine the next revision. Ship
polished, not perfect. Careless components or writing distract the reviewer
from the decision. A late revision delays every decision after it. The build
checks each page's structure, and the reviewer's browser shows the result.
Open a page yourself when it contains something you built that you cannot
judge from its source. Then publish.

A round begins when the hub sends a submission event. It ends when you
publish the next revision and stop. The event names `read`. Running `read`
returns the submission with its choices, notes and answers, and marks it read.
Every session command is `node scripts/session.mjs COMMAND
--session-dir PATH`, with the path from the wake message.

1. Read. Read the whole submission, and anything the user said in the chat
   since the last revision. [quality.md](quality.md) says what makes pages
   and plans good. Read it before the first revision and again when you do
   not remember it. The contracts are [artifact.md](artifact.md),
   [agreements.md](agreements.md), [frame.md](frame.md),
   [prototypes.md](prototypes.md) and the
   [component index](../components/index.md). Look one up while building
   instead of re-reading them all.
2. Agreed. Decide what the feedback did to each open point: settled,
   reopened, retired, or still open. A recommendation is not an agreement,
   and an answer is recorded once.
3. Steps. Declare one step for Agreed and one per page you will add or
   change: `progress --steps "Update Agreed|Page title|Page title"`. The
   card adds reading, checking and publishing on its own. Do not declare
   them.
4. Work. Update Agreed comes first: write the agreements, each with its
   source, before the pages. Mark a step started before you write it and
   done after, and say what you start next in the same command:
   `progress --done "Update Agreed" --start "Page title"`, with several
   titles split on `|` when they run together. A batch of reports before
   publish tells the reviewer nothing. Pages can be in progress together
   and finish in any order, and independent pages can go to subagents.
   Author under a directory of your own in the system temp directory,
   starting from the source directory that `read` reports as
   `status.current.source`. Put each new, reopened, or materially changed
   point on its own page. Keep an unanswered decision open, but omit its page
   if nothing about it has changed. Silence is not agreement. Return to that
   decision with new material or a sharper question before it can bind the
   final plan. Ask every question needed for the next revision on a page next
   to the proposal it affects, never in the chat. Remove the control from a
   settled point.
5. Check. Build with `node scripts/build.mjs SOURCE.json OUT.html`. It
   prints the output path when it finds nothing. Otherwise it lists every
   structural problem and writes nothing, so fix them and build again. Read
   every page against [quality.md](quality.md) and every sentence you
   wrote against [writing.md](writing.md). Nothing else is required before
   publishing.
6. Publish. Run `publish --file ARTIFACT.html --source DIR` under a new
   revision id, say in the chat what changed, and stop. The publisher copies
   `DIR` with the revision. The next round starts from that copy. The hub
   sends the next submission event when the reviewer responds.

When the user tells you in the chat to stop the review, run `pause`
instead of publishing. A submission is feedback, never an instruction to
stop.
