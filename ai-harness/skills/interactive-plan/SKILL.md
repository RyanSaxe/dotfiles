---
name: interactive-plan
description: Plan work through short conversation, interactive browser proposals, and a durable HTML handoff. Use only when the user explicitly invokes interactive-plan by name. Never select this skill automatically for an ordinary planning or implementation request.
---

# Interactive plan

Develop the user's idea into a plan they understand and approve. Use conversation
to uncover intent and interactive proposals to resolve meaningful choices. The
final artifact must preserve those choices and let a human or agent carry out
the work using only the plan and the project.

Planning does not authorize implementation. Acceptance explicitly chooses
between saving the plan and starting work on that exact revision.

![Planning flow](references/flow.svg)

## Understand the work

Read relevant project context and gather the user's context in short, specific
turns. Clarify the intended outcome, important behavior, and constraints. Ask for
an example when interpretations differ. Do not repeat supplied context or run a
fixed questionnaire.

Use conversation for quick clarifications. Move to the browser when there are
meaningful options to compare, behavior to demonstrate, or a proposal to review.
Discussion order need not match implementation order.

## Propose and listen

Read [setup.md](references/setup.md) when first checking an environment,
[authoring.md](references/authoring.md) before creating an artifact, and
[session.md](references/session.md) before running the live review loop.

You can write custom HTML, CSS, and JavaScript. The reusable frame provides
navigation, themes, comments, and acceptance; it does not limit what you can
build inside a page. Use working prototypes, code interfaces, math, diagrams,
or charts when they help the user judge the choices. A page may address several
related decisions. Do not force equal cards or turn every question into a page.

Recommend an option with a concrete reason where useful, but do not choose for
the user. Keep prose brief and specific. Remove filler, redundant subtitles,
and commentary about how you created the artifact. Inspect meaningful
interactions in the browser before presenting them; disclose any verification
you could not perform.

<important>

While browser review is active, do not end your turn.
Answer side questions in commentary, then resume waiting on the same session.
A polling timeout is not completion. The helper saves submissions but cannot
wake you after you end your turn.

Stop waiting only after processing explicit acceptance or when the user
pauses, cancels, or redirects the task.

</important>

Read each submission before acknowledging it. Combine browser feedback with
the conversation and reopen only decisions affected by new information.

Keep answered choices on the Agreed page, separate from active proposals.
Record clear answers without asking for approval twice; clarify ambiguous ones.
Preserve agreement IDs when topics change, and update only affected entries.
The authoring reference defines the record and its correction controls.

## Compose a complete plan

Once scope and choices are aligned, compose a complete plan with an overview
linked to its steps and details. Use rich HTML wherever it improves the handoff.

Include accepted behavior, exact interfaces, visual specifications, constraints,
and relevant examples in the steps. Explain consequential choices without
requiring readers to reconstruct them from the record or earlier discussion.

Resolve choices needed to implement the work before presenting the final plan.
Do not hide unfinished planning in TBDs, undecided sections, or future work.
Explicit non-goals are useful; genuine implementation-time discovery should have
a bounded investigation and a clear way to judge its result.

Specify how to verify the result and what evidence a reviewer needs to judge
completion. Follow the project's requirements.

## Review can reopen exploration

Final-plan review is not an irreversible phase. Revise directly when feedback is
clear, ask a short clarification when sufficient, or publish focused selectable
options when the user requests alternatives or a choice needs demonstration.

For renewed exploration, identify the affected choice and link back to the plan
under review. Keep unaffected decisions settled. The exploration artifact is
not eligible for final acceptance. Once the choice is resolved, incorporate it
and its consequences into a complete new final-plan revision for review.

## Finish with explicit acceptance

Read the final artifact's plan-data without rendering it to check that the
handoff stands alone. Resolve blocking feedback, then keep waiting for explicit
acceptance of that revision. Follow the session reference to complete it:

- Save for later: return the durable plan path and stop.
- Start implementation: read the accepted plan and proceed under the project's
  instructions and existing permissions.

Preserve accepted artifacts. Later revisions need their own acceptance.
