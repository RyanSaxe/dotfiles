---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

Develop an implementation-ready plan with the user. Read the project and
conversation to distinguish settled requirements from open decisions. Show the
design, behavior, code, or wording they need to judge, and use their responses
to revise the proposal. You will very likely want to have a discussion with the
user to get the necessary context before you can do a good job creating
interactive HTML pages to iterate with them.

## Explore, then review

Planning has two phases: exploration and review.

During exploration, develop the proposal with the user and resolve the choices
needed for a complete implementation plan. Exploration may cover a narrow
question, several connected choices, or a broad part of the proposed work.

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

Ask only for missing information that affects the plan. Move to the browser
when there is concrete material to compare, correct, or approve.

- Read [setup.md](references/setup.md) on first use in an environment or when a capability fails.
- Read [authoring.md](references/authoring.md) before building an artifact.
- Read [session.md](references/session.md) before starting or resuming live review.

Build the artifact and review its source before publication. Use the live
browser session to find and correct rendering or interaction problems. Browser
automation is optional; do not install it to author a plan unless asked. Open
the first proposal in the user's default browser and provide its link. Keep
the session for revisions.

Read submissions before acknowledging them and combine them with conversation
feedback. Record clear answers without asking twice. Keep settled decisions on
Agreed with stable IDs and exact sources. Reopen only affected decisions.
Recommendations are not agreements. When a revision changes substantive
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
