---
name: interactive-plan
description: Develop and review implementation plans in an interactive browser session. Use only when the user explicitly invokes interactive-plan by name, never for ordinary planning requests.
---

# Interactive plan

Work with the user toward an implementation-ready plan. Read the project and
conversation to distinguish settled requirements from open decisions. Show the
actual design, behavior, code, or wording they need to judge. Their responses
must shape the plan, not merely approve a solution you have already chosen.

## Make the discussion worth seeing

Lead with the proposal and what needs judgment. Keep the evidence and
consequences beside it, not behind a report the user must read first.

Offer alternatives only when each has a credible reason to be chosen. Explain
your recommendation without weakening the other options to make it win. When
behavior differs, show the difference on comparable inputs instead of describing
styles in the abstract. Leave room for correction or a different proposal.

Design each page so the user can scan the proposal, compare its consequences,
and respond. Use well-designed components to bring related content and controls
together. Prefer them to long text blocks when they make the decision clearer.
Keep the explanation the decision needs; avoid decoration and empty space that
separate it from the proposal.

Start with the supplied components when they fit. Adapt them or build your own
when another design communicates the plan better. These editable implementations
support page composition; they do not prescribe layouts, sample arguments, or
the only components allowed. See the [component index](components/index.md) when
choosing sources to reuse.

A text dump with buttons is insufficient. So is a polished demonstration that
does not help the user shape the plan. Make controls recognizable, their targets
clear, and selection visible. Demonstration controls are not planning decisions
unless their values change the proposed implementation.

The frame supplies navigation and review mechanics, not page templates. Compose
each page freely, using its theme, clear typography, spacing, and alignment.
Use the available renderers, including syntax highlighting for code. Do not
substitute decorative effects for useful visual explanation.

## Propose and iterate

Ask only for missing information that affects the plan. Move to the browser when
there is concrete material to compare, correct, or approve.

- Read [setup.md](references/setup.md) on first use in an environment or when a capability fails.
- Read [authoring.md](references/authoring.md) before building an artifact.
- Read [session.md](references/session.md) before starting or resuming live review.

Inspect the rendered page and exercise its meaningful interactions, renderers,
themes, and narrower layouts. Can the user scan what is proposed, what remains
open, and how their response would change it?

Open the first proposal in the user's default browser and provide its link.
Keep the same session for revisions. Read submissions before acknowledging them;
combine them with conversation feedback. Record clear answers without asking
twice. Keep settled decisions on Agreed, preserve their IDs and exact sources,
and reopen only affected decisions. Recommendations are not agreements.

<important>

While browser review is active, keep the turn waiting on that session. Answer
side questions, then resume waiting. A timeout is not completion; the helper
cannot wake an ended turn. Stop only after explicit acceptance or when the user
pauses, cancels, or redirects the task.

</important>

## Deliver the agreed plan

Compose an overview linked to implementation steps. Include accepted behavior,
interfaces, constraints, and task-specific verification. Resolve critical choices
before final review; bound genuine implementation-time discovery with a way to
judge its result.

Preserve approved wording, code, formulas, and interfaces exactly unless a later
decision changes them. Keep approved designs viewable and interactions usable,
with their source and essential resources embedded in the relevant step. Neither
summaries, screenshots alone, nor history links replace the approved material.
Distinguish binding requirements from illustrations and unfinished integration.

Check that the final artifact and project suffice to implement the plan without
earlier revisions or conversation. Inspect preserved material and extract its
source from plan-data. If review reopens a decision, incorporate the resolution
into a complete new final revision before acceptance.

Planning does not authorize implementation. Follow the session's explicit
acceptance mode: save and return the durable path, or read the accepted artifact
and begin implementation under project instructions and existing permissions.
Preserve accepted artifacts; later revisions need their own acceptance.
