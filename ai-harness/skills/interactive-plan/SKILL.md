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
  phase, how Agreed is kept, how to revise, how a plan reaches review, and
  the sentence check. Read it before authoring.
- [authoring.md](references/authoring.md) and the
  [component index](components/index.md): the artifact contracts, what a
  revision may change, and the supplied components. Read them before
  building.
- [session.md](references/session.md): the helper, the hub, the wake paths,
  and acceptance. Read it before starting or resuming a live review.
- [setup.md](references/setup.md): on first use in an environment, or when
  something fails.

## Run the session

Ask in conversation only for information that is missing and affects the
plan. Put every other request for input on a page, next to the proposal it
affects. Move to the browser once there is concrete material to compare,
correct, or approve. Open the first proposal in the user's default browser
and give the link in chat.

Browser automation is optional. Use the live page to find and fix rendering
and interaction problems. Do not install automation to author a plan unless
asked.

<important>

While browser review is active, a turn ends after `publish` or after
`pause`. The hub wakes you when a submission lands, acceptance included,
and nothing else does. `complete` ends the review, and the accepted mode
says what follows. When `start` refuses because the session cannot be
woken, give the user the instruction it prints and stop until the session
is restarted. Stop a review before acceptance only when the user says in
words to stop, and then run `pause`, so the page says that the agent
stopped and how to resume it.

</important>

Acceptance names a mode, save or implement. Follow that mode and the
project's permissions. Accepted artifacts stay as they are. Later revisions
need their own acceptance.
