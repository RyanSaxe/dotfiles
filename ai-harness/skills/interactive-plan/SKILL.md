---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

interactive-plan helps an agent develop an implementation-ready plan with the
user in the browser. The agent puts open decisions and the material needed to
judge them on pages. The user answers by choosing options and commenting on
text or components. The agent revises the plan until the user accepts it.

During exploration, the agent settles one decision per topic. The Agreed page
lists each settled decision and its source. Review presents the complete plan
with an overview page and one page per implementation step. The plan contains
enough information to implement and verify the work without earlier revisions
or the conversation. If feedback reopens a settled choice, return to
exploration before presenting another complete plan.

## Files

- [round.md](references/round.md): the sequence for each revision. The hub's
  wake message names it.
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

The session begins in the conversation. Before the first revision, establish
what the user wants, what they do and do not want, what the project shows and
what remains uncertain. Ask one question at a time and use each answer before
asking the next question. Move to the browser once there is material to
compare or approve. Open the first revision in the user's default browser and
give the link in chat. Ask every later question on a page.

After `publish` or `pause`, the turn ends. The hub starts another turn when a
submission arrives, including an acceptance. `complete` ends the review. If
the user closes a session in the browser, the hub sends no further wake event
for that session. When `start` refuses because the harness cannot receive a
wake event, give the user the printed instruction and wait for a restart.

An acceptance specifies `save` or `implement`. Follow that mode and the
project's permissions. Do not change an accepted artifact.
