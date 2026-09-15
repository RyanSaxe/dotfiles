---
name: interactive-plan
description: Plan work through conversation, rich interactive browser proposals, and a complete HTML handoff. Use only when the user explicitly invokes interactive-plan by name. Never select this skill automatically for an ordinary planning or implementation request.
---

# Interactive plan

Work with the user to develop an implementation-ready plan. Use their request, project context, and prior decisions to identify what still needs discussion. Do not ask them to approve settled requirements again.

Make that discussion concrete. Show the proposed design, behavior, code, or wording that the user needs to judge. Explain consequential tradeoffs and recommend an approach when you have a reason. Offer alternatives when they represent real choices, and leave room for the user to reject the framing or propose something else.

Give the planning discussion a rich, carefully composed visual form. Make relationships, alternatives, and consequences easy to grasp by scanning and interacting. Keep the explanation needed to judge the proposal. Remove content that does not help the discussion; compressing it into a short label or decorative element does not make it useful. A text dump with buttons is not an acceptable result; neither is a polished demonstration that does not help the user shape the plan.

Use each response to revise the plan and its affected decisions. Preserve what is settled, identify what remains unresolved, and continue until the user can approve a complete plan. Do not turn the exchange into a presentation of a solution you have already chosen.

Planning does not authorize implementation. Acceptance explicitly chooses between
saving the plan and starting work on that exact revision.

## Compose the discussion

Choose the representation from the decision being discussed. Text, tables,
diagrams, code, and working previews can each carry part of the explanation.
Use the supplied renderers where appropriate and custom HTML, CSS, JavaScript,
or SVG when needed. Do not add a visualization or interaction merely to make
the page look interactive.

Put selection controls beside the material they select. Make the consequences
of an option visible before asking the user to choose. A demonstration control
is not a planning choice unless its value changes the proposed implementation.
Support corrections and discussion when predefined alternatives would constrain
the user's answer.

Use clear typography, spacing, alignment, and emphasis. Follow the frame's color
scheme and light/dark themes. Avoid decorative gradients, unrelated palettes, and
distracting effects. Each plan should feel composed for this conversation.
Use specific headings and labels; remove redundant subtitles, vague phrases,
and prose about how to read or operate the page.

The shared frame provides navigation, orientation, and review mechanics. It does
not prescribe page composition. Do not force equal cards or one decision per page.

## Understand and propose

Read relevant project context. Gather the user's intent, important behavior, and
constraints in short, specific turns. Do not repeat supplied context or run a
fixed questionnaire. Move to the browser when there are meaningful options to
compare, behavior to demonstrate, or a proposal to review.

Read [setup.md](references/setup.md) when first checking an environment,
[authoring.md](references/authoring.md) before creating an artifact, and
[session.md](references/session.md) before running the live review loop.

Inspect the actual page before presenting it. Can the user tell what is proposed,
what remains open, and how their response would change the plan? Check that the
composition makes those judgments easier without hiding necessary explanation.
Exercise meaningful interactions and renderers in the
affected themes and smaller layouts. Disclose verification you could not perform.

Open the first published proposal in the user's default browser and provide its
link. Keep the same session for subsequent revisions.

<important>

While browser review is active, do not end your turn. Answer side questions in
commentary, then resume waiting on the same session. A polling timeout is not
completion; the helper cannot wake you after you end your turn.

Stop waiting only after processing explicit acceptance or when the user pauses,
cancels, or redirects the task.

</important>

Read each submission before acknowledging it. Combine browser feedback with
conversation context. Record clear answers without asking for approval twice;
clarify ambiguous ones. Keep settled choices on Agreed, separate from active
proposals. Preserve agreement IDs and reopen only affected decisions.

Use source references to retain exact browser comments and choices. A synthesized
agreement can have several sources. Label conversation context honestly rather
than inventing browser evidence. Sources support the interpretation; they do not
establish agreement by themselves.

## Preserve the approved work

When the user approves a visual design, prototype, interface, code fragment,
formula, or other concrete material, preserve it for the final plan. Carry it into
the relevant implementation step. Do not replace it with a summary, a screenshot
alone, or a link to an earlier revision.

Keep approved code and interfaces verbatim unless a later decision changes them.
Keep visual designs directly viewable and approved interactions usable. Embed
their source and required local resources so a human or agent can recover the
specification from the final artifact alone. The authoring reference describes
self-contained prototypes and their source views.

State which details are binding and which are illustrative. Describe remaining
implementation work and accepted changes to a preserved prototype. Fix assembly
drift or reopen the affected decision. Approval of a sketch does not decide
unspecified behavior.

## Compose and review the complete plan

Once scope and choices are aligned, compose an overview linked to implementation
steps. Preserve the same visual and writing quality throughout the final plan.
Include accepted behavior, exact interfaces, viewable designs, constraints,
necessary explanation, and task-specific verification requirements in the steps.
The agreement record and history links do not replace this material.

Resolve implementation-critical choices before final review. Do not hide
unfinished planning in TBDs or future work. Bound genuine implementation-time
discovery with a way to judge its result.

Final review can reopen exploration. Revise directly when feedback is clear,
clarify briefly when sufficient, or publish focused options when alternatives
need demonstration. Identify the affected choice and link back to the plan.
Exploration cannot be accepted as a final plan. Incorporate the resolution and
its consequences into a complete new final revision.

## Finish with explicit acceptance

Inspect every preserved item in the final artifact and extract its source without
earlier files or conversation. Read plan-data without rendering it. Confirm that
the approved work, its binding requirements, and completion evidence are present
together. Resolve blocking feedback and keep waiting for acceptance of that revision.

Follow the session reference:

- Save for later: return the durable plan path and stop.
- Start implementation: read the accepted artifact and proceed under project
  instructions and existing permissions.

Preserve accepted artifacts. Later revisions require their own acceptance.
