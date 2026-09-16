# Planning quality

## Exploration quality

Exploration may address a narrow question, several connected choices, or a broad
part of the proposed work. Keep related parts together when their interaction
matters. Separate them when an unresolved dependency or too much material would
make the proposal hard to assess.

Resolve routine details from project evidence and settled requirements. Ask the
user about choices that change intended behavior, scope, an interface, or an
important tradeoff. Address choices that affect later options before spending
time on details those choices could invalidate.

When a topic contains a meaningful choice, present a small set of credible
options, usually two to four. Recommend one and make the basis for that
recommendation visible in the comparison. Let the user choose, combine, revise,
or reject the options. Do not invent alternatives when only one direction is
credible.

Treat components as first-class planning tools. Build with them from the start
instead of writing a prose proposal and wrapping it in boxes afterward. Inspect
the component index before composing a page and use supplied components
frequently when they fit. Adapt them or create a new component when the content
needs a different structure or interaction.

Build each topic page around the proposal itself. Render or demonstrate the
material when the browser can do so, and use prose for context or consequences
that the page cannot show. Let the content determine the layout. Keep the
recommendation, evidence, and feedback controls beside the material they affect.
Do not lead the page with a generic explanation.

Keep component-specific guidance in the component index. Document a new
component's purpose and implementation there; adding one should not require new
workflow text in this file or `SKILL.md`.

Use visual hierarchy and color to direct attention and make relationships clear.
Do not make color the only carrier of meaning. Avoid decorative cards, labels,
tags, and pills that merely repeat nearby text or name a section. Keep feedback
controls beside their target and use the frame's existing submission flow.

Good exploration lets the user understand and correct the proposal without
hiding how its parts affect one another. It does not need to cover the whole
plan or divide the work into one choice at a time.

## Review quality

Present the complete plan as an implementation handoff. Organize it around the
changes an engineer will make, not the order in which the discussion happened.

Begin with an overview page that makes the intended outcome, scope, and
relationships among the implementation steps clear. Link to each step. Use
visual structure or a diagram when it communicates those relationships better
than prose.

Each step should state the behavior it must produce and how that behavior will
be verified. Include dependencies, exact interfaces, approved material, and
constraints where they affect implementation. Distinguish binding requirements
from illustrations and unfinished integration work.

Use components and visual structure to make the plan easier to navigate and
inspect. Preserve approved wording, designs, and interactive behavior in the
relevant step. Do not replace material the implementer needs with a summary,
screenshot, or link to an earlier proposal.

Keep verification with the work it covers. Name what must be demonstrated and
the interface through which it will be checked. Distinguish automated checks
from behavior that requires direct use.

Resolve implementation-critical unknowns during exploration by inspecting the
project or reviewing the available directions with the user. If something
genuinely cannot be known until implementation, explain why, state what must be
investigated, and define an acceptable result.

The plan and project must provide everything needed to implement and verify the
agreed work without relying on earlier proposals or conversation. Match the
detail to the work; do not expand routine mechanics merely to make the plan look
comprehensive.

## Revisions

When revising material the user has already seen, show the new version against
the version they reviewed. Use an exact diff for text or code. Keep visual
before-and-after views comparable and identify what changed. A short explanation
may give the reason for the revision, but it does not replace the comparison.

Preserve earlier revisions so submitted feedback remains attached to what the
user saw. Open the rendered artifact and use it before publication. See the
[component index](../components/index.md) for supplied implementations and
[authoring.md](authoring.md) for integration contracts.
