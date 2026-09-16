# Planning judgment and component design

## Choose the decisions

Resolve routine details from project evidence and settled requirements. Ask the
user when their answer changes intended behavior, scope, an interface, or a
consequential tradeoff. Resolve decisions that change later options first. Group
choices whose combined effect matters; postpone details an earlier answer could
invalidate.

Recommend an approach and explain the consequence that favors it. Offer
alternatives only when each has a credible reason to be chosen. Show different
behavior on comparable inputs. Keep the evidence and consequences beside the
proposal, and leave room to correct its framing or suggest another approach.

## Reuse, adapt, or create components

Start with the judgment the user needs to make and the response that would
change the plan. Choose the representation and interaction that make this
relationship clear. Inspect relevant supplied components before deciding how
to compose the page. Reuse their implementation when it fits, adapt it for the
content, or design a new component when that would communicate better.

Build around the actual material being reviewed. Keep related evidence,
alternatives, and controls together. Make consequential differences visible
before asking for a choice. Use the existing renderers within components when
they explain code, relationships, formulas, or data. Do not add an interaction
merely to make a page interactive.

Make controls recognizable and their targets and selected states clear. Separate
demonstration state from planning responses. Prefer clear labels, placement, and
visible state to explanatory text about operating the interface. Add explanation
when it conveys a consequence or behavior the controls cannot show.

Use native HTML, CSS, and JavaScript with the frame's theme and feedback hooks.
Keep keyboard focus usable and meaning independent of color. Check the authored
source and use live review to correct interaction or rendering problems. Browser
automation is optional. See [authoring.md](authoring.md) for integration contracts.

The supplied components provide reusable interactions and styling. They are not
a complete menu of what can be built. Keep task-specific sample arguments and
finished page layouts out of the reusable guidance.

## Compose the complete plan

Begin with an overview that explains the intended outcome, scope, and how the
changes fit together. Link it to implementation steps. Use an architecture
diagram or other visual when it explains meaningful relationships; choose the
form from the work rather than a fixed outline.

Make each step a coherent change with its required behavior and verification.
Include dependencies, exact interfaces, approved material, and constraints where
they affect implementation. Use as many steps as the work needs. Separate
binding requirements from illustrations and remaining integration work.

Put verification beside the relevant work. State what must be demonstrated and
through which interface. Distinguish automated checks from behavior that needs
direct use. Add an overview summary when needed to explain how the combined
result will be checked.

Resolve implementation-critical choices before final review. For details that
require implementation-time investigation, state what to investigate and what
result would be acceptable. The plan and project must suffice to implement and
verify the work without relying on earlier proposals or conversation.
