---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

interactive-plan helps an agent and a user plan a piece of work together in
the browser. The agent's job is to close the ambiguity between the request
and a plan that another engineer could implement. Some of it is in the task,
what is being built and why, and some is in the work, how to build it.
Ambiguity in the task usually has to close first, because the work depends
on it, but either kind can surface at any point.

Each revision puts that ambiguity on pages as proposals, options and
questions, with the material needed to judge them. People judge by looking,
so a page shows its subject with mocks, diagrams, code and diffs, and uses a
visual decision when the options differ in something the reviewer could
see. The user answers by choosing options and commenting on anything.

Agreed opens with the task: a title and a few sentences on what the plan is
building towards, as the agent currently understands it. It is not a list of
decisions. The user corrects it by
commenting, like anything else, and the agent never asks them to approve
it. The settled decisions follow it, each with its source. When nothing in
the task or the work is left to decide, the agent presents the complete
plan, starting with an overview page. The user accepts it or sends
feedback. If feedback reopens a settled choice, return to exploration before
presenting another complete plan.

An engineer or agent who saw none of the revisions and none of the
conversation implements the final plan. Every approved look, wording,
interface and behavior appears in the plan itself, updated to match
everything agreed after it was shown. An approved mock is shown in the plan,
not described.

## Files

- [round.md](references/round.md): the sequence for each revision. The hub's
  wake message names `ack`, which points to it.
- [quality.md](references/quality.md): what makes a page and a plan good.
  Read it before the first revision.
- [writing.md](references/writing.md): the rules every sentence follows.
- [session.md](references/session.md): starting, resuming and accepting a
  session. Read it before `start`.
- [component index](components/index.md): every component and its markup.
  A page copies a component's markup and nothing else.
- [components/README.md](components/README.md): writing a component, when a
  page needs one or the user asks to keep one.
- [artifact.md](references/artifact.md), [agreements.md](references/agreements.md),
  [frame.md](references/frame.md) and
  [prototypes.md](references/prototypes.md): the contracts. Look one up
  while building.
- [setup.md](references/setup.md): on first use in an environment, or when
  starting, waking or a command fails.

## Opening

The session begins in the conversation. Before the first revision, establish
what the user wants, what they do and do not want, what the project shows and
what remains uncertain. Ask one question at a time and use each answer before
asking the next question. Move to the browser once there is material to
compare or approve. When the first Agreed publishes, open the session in the
user's default browser and give the link in chat. Ask every later question on
a page.

After the last page of a revision publishes, or after `pause`, the turn ends.
The hub starts another turn when a submission arrives, including an
acceptance. `complete` ends the review. When `start` refuses because the
harness cannot receive a wake event, give the user the printed instruction
and wait for a restart.

An acceptance specifies `save` or `implement`. Follow that mode and the
project's permissions. Do not change an accepted artifact.
