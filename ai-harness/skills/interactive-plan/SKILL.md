---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

Develop an implementation-ready plan with the user in the browser: show the
decisions and the material needed to judge them, take feedback, and revise
until the user accepts.

## Two phases

Exploration settles open decisions. Its pages hold the choices under review
and the material needed to make them; Agreed holds what is settled, with
exact sources. Review presents the complete plan: an overview linked to
implementation steps that an engineer or agent can implement and verify from
the plan and the project alone.

Both phases take as many revisions as they need. Apply clear corrections
directly. When feedback reopens a choice that needs comparison, return to
exploration and carry the result into a complete new plan before acceptance.
The [review flow](references/flow.svg) shows the loop.

## What to read

- [planning.md](references/planning.md): what goes on the pages in each
  phase, and how to revise. Read it before authoring.
- [authoring.md](references/authoring.md) and the
  [component index](components/index.md): the artifact contracts and the
  supplied components. Read them before building.
- [session.md](references/session.md): the helper, the hub, and acceptance.
  Read it before starting or resuming live review.
- [setup.md](references/setup.md): on first use in an environment, or when a
  capability fails.

## Run the session

Ask in conversation only for missing information that affects the plan; put
every other request for input on a page, beside the proposal it affects. Move
to the browser when there is concrete material to compare, correct, or
approve. Open the first proposal in the user's default browser and give the
link in chat.

Read each submission before acknowledging it and combine it with feedback
from the conversation. Record clear answers once. Reopen only affected
agreements; recommendations are not agreements. When a revision changes
substantive content, say what changed and link to it.

Browser automation is optional. Use the live page to find and correct
rendering and interaction problems; do not install automation to author a
plan unless asked.

<important>

While browser review is active, keep the turn waiting on that session. Answer
side questions, then resume waiting. A timeout is not completion; the helper
cannot wake an ended turn. Stop only after explicit acceptance or when the user
pauses, cancels, or redirects the task.

</important>

Acceptance chooses save or implement explicitly. Follow the mode and the
project's permissions. Accepted artifacts stay as they are; later revisions
need their own acceptance.
