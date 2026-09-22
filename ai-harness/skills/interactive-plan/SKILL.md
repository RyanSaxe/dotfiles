---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

interactive-plan develops an implementation-ready plan with the user in the
browser. The agent puts the open decisions and the material needed to judge
them on pages, the user answers by choosing options and by commenting on
any text or component, and the agent revises until the user accepts.

Exploration settles the decisions, one page per topic, with the Agreed page
holding what is settled and where each agreement came from. Review presents
the complete plan: an overview page and one page per implementation step,
enough to implement and verify the work from the plan and the project
alone. Feedback that reopens a settled choice goes back to exploration
before a new complete plan is presented.

## Files

- [round.md](references/round.md): what every revision does, in order. The
  hub's wake message names it.
- [quality.md](references/quality.md): what makes a page and a plan good.
  Read it before the first revision.
- [writing.md](references/writing.md): the rules every sentence follows.
- [session.md](references/session.md): starting, resuming and accepting a
  session, and the hub. Read it before `start`.
- [artifact.md](references/artifact.md), [agreements.md](references/agreements.md),
  [frame.md](references/frame.md), [prototypes.md](references/prototypes.md)
  and the [component index](components/index.md): the contracts. Look one
  up while building.
- [setup.md](references/setup.md): on first use in an environment, or when
  something fails.

## Opening

The session begins in the conversation. Before the first revision, get the
context the plan needs: what the user wants, what they already know they
want and do not want, what the project shows, and what is uncertain. That
is a back and forth, not a list of questions. Move to the browser once
there is material to compare or approve, open the first revision in the
user's default browser, and give the link in chat. From then on, anything
the plan needs from the user is asked on a page.

A turn ends after `publish` or `pause`; the hub starts the next one when a
submission lands, acceptance included, and `complete` ends the review. The
user can also close a session from the browser, and then no next turn
comes. When `start` refuses because the session cannot be woken, give the
user the instruction it prints and stop until the session is restarted.

Acceptance names a mode, save or implement. Follow that mode and the
project's permissions. Accepted artifacts stay as they are.
