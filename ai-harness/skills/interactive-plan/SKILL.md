---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

interactive-plan develops an implementation-ready plan with the user in the
browser. The agent shows the decisions and the material needed to judge
them, takes feedback, and revises until the user accepts.

## Two phases

Exploration settles the open decisions. Its pages hold the choices under
review and the material needed to make them. The Agreed page holds what is
settled, with a link to the exact place each agreement came from. Review
presents the complete plan: an overview page linked to implementation
steps that an engineer or agent can implement and verify using only the
plan and the project.

Both phases take as many revisions as they need. Apply clear corrections
directly. When feedback reopens a choice that needs comparison, return to
exploration, settle it, and carry the result into a complete new plan
before acceptance. The [review flow](references/flow.svg) shows the loop.

## What to read

- [planning.md](references/planning.md): what goes on the pages in each
  phase, how to revise, and the sentence check. Read it before authoring.
- [authoring.md](references/authoring.md) and the
  [component index](components/index.md): the artifact contracts and the
  supplied components. Read them before building.
- [session.md](references/session.md): the helper, the hub, and acceptance.
  Read it before starting or resuming a live review.
- [setup.md](references/setup.md): on first use in an environment, or when
  something fails.

## Run the session

Ask in conversation only for information that is missing and affects the
plan. Put every other request for input on a page, next to the proposal it
affects. Move to the browser once there is concrete material to compare,
correct, or approve. Open the first proposal in the user's default browser
and give the link in chat.

Read each submission before acknowledging it, and combine it with feedback
from the conversation. Right after `ack`, declare the steps of the revision
with `progress --steps` and mark each one with `--done` as you finish it.
The reviewer's page shows them, with reading, checking and publishing
already around them. Record a clear answer once. Reopen only the agreements
the feedback affects; a recommendation is not an agreement. When a revision
changes substantive content, say what changed and link to it. Before
publishing, check every sentence on the pages against the list at the end
of planning.md.

Browser automation is optional. Use the live page to find and fix rendering
and interaction problems. Do not install automation to author a plan unless
asked.

<important>

While browser review is active, every turn ends with a `wait` in flight or
with `complete`. A timeout is not completion: wait again. A side question in
the conversation does not end the session: answer it, then call `wait`
again in the same turn. An interrupted or rejected `wait` means the user
wants attention, not that the review is cancelled: answer, then wait again.
The helper cannot wake an ended turn, and the user cannot see that polling
stopped, so a turn that ends without a wait leaves the session dead without
anyone knowing. Stop only after explicit acceptance, or when the user says
in words to stop or redirects the task, and say in the reply that polling
has stopped.

</important>

Acceptance names a mode, save or implement. Follow that mode and the
project's permissions. Accepted artifacts stay as they are. Later revisions
need their own acceptance.
