---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

Develop an implementation-ready plan with the user. During exploration, show
the unresolved decisions and the material needed to settle them. Save the
overview and implementation steps for the final plan. Keep settled decisions on
Agreed with stable IDs and exact sources.

## Explore, then review

Planning has two phases: exploration and review.

During exploration, develop the proposal with the user and resolve the choices
needed for a complete implementation plan. Exploration pages contain decisions
under review, not a generic overview or early implementation steps. Agreed is
the running context for settled work; do not add a Brief or equivalent page.

During review, present the complete implementation plan. Scope and
implementation-critical choices must be settled. The plan must include
everything needed for an engineer or agent to implement and verify the agreed
work using only the plan and project.

Both phases may take several revisions. Apply clear corrections directly. When
feedback reopens a choice that needs comparison, return to exploration. Carry
the result into a complete new plan before acceptance. The
[review flow](references/flow.svg) shows both phases and their shared review loop.

Read [planning.md](references/planning.md) before developing exploration
artifacts or composing the complete plan. It covers the content and visual
quality of both phases.

## Run the session

Every live session is served by one local hub at one address. `start` returns
at once with the session's URL; there is no long-running helper process to
keep open. Place each request for input beside the proposal it affects, using
the question component when the answer is prose. The user answers through
normal feedback or in the agent conversation. Do not open a separate question
channel. Move to the browser when there is concrete material to compare,
correct, or approve.

- Read [setup.md](references/setup.md) on first use in an environment or when a capability fails.
- Read [authoring.md](references/authoring.md) before building an artifact.
- Read [session.md](references/session.md) before starting or resuming live review.

Build the artifact and review its source before publication. Use the live
browser session to find and correct rendering or interaction problems. Browser
automation is optional; do not install it to author a plan unless asked. Open
the first proposal in the user's default browser and provide its link. Keep
the session for revisions; the page refreshes itself when a revision lands.

Read submissions before acknowledging them and combine them with conversation
feedback. Record clear answers without asking twice. Reopen only affected
agreements. Recommendations are not agreements. When a revision changes substantive
content, briefly explain the changes and link to them where that helps review.

<important>

While browser review is active, keep the turn waiting on that session. Answer
side questions, then resume waiting. A timeout is not completion; the helper
cannot wake an ended turn. Stop only after explicit acceptance or when the user
pauses, cancels, or redirects the task.

</important>

## Deliver the agreed plan

Compose an overview linked to implementation steps, following planning.md.
Preserve approved wording, code, formulas, and interfaces exactly unless a later
decision changes them. Keep approved designs viewable and interactions usable,
with their source and essential resources embedded in the relevant step.
Distinguish requirements from illustrations and unfinished integration.

Check that the final artifact and project suffice to implement the plan without
earlier revisions or conversation. Inspect preserved material and extract its
source from plan-data. Summaries, screenshots alone, and history links cannot
replace approved material.

Acceptance explicitly chooses between saving the plan and starting its
implementation. Follow the session's acceptance mode and existing project
permissions. Preserve accepted artifacts; later revisions need their own acceptance.
