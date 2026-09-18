# Planning quality

## Exploration

Exploration pages settle open decisions. Do not add an overview page, early
implementation steps, or a summary page. Agreed is the only running context;
it holds settled decisions with their exact sources.

An exploration may address one decision, several connected choices, or a broad
part of the proposal. Keep related parts together when their interaction
matters; separate them when an unresolved dependency or too much material
would make the proposal hard to assess. Address choices that affect later
options before spending time on details those choices could invalidate.

Resolve routine details from project evidence and settled requirements. Ask
the user about choices that change intended behavior, scope, an interface, or
an important tradeoff, and ask on the page: a decision for a selection, a
question for prose, always beside the proposal it affects.

When a topic contains a meaningful choice, present a small set of credible
options, recommend one, and make the basis for the recommendation visible in
the comparison. Do not invent alternatives when only one direction is
credible. Selecting an option must change the nearby proposal, behavior,
diagram, wording, or tradeoff; a row of labeled text blocks is not a
comparison. Use the decision component when a title and one line are enough
to judge each option, and the visual decision when each option needs a
diagram, code, chart, or prototype.

A page starts at the decision. No lede, no sentence of rationale, no
restatement of the question; at most one line of context about what a mock
shows. Each option carries one line of consequence. A sentence that could
sit unchanged on another plan says nothing about this one.

Build each page around the proposal itself. Render or demonstrate the
material when the browser can, and use prose for context or consequences the
page cannot show. Let the content determine the layout, keep the
recommendation, evidence, and feedback controls beside the material they
affect, and do not lead with a generic explanation. Choose supplied
components by purpose from the [component index](../components/index.md),
adapt them, or build a plan-local one when the material needs a different
structure. Component guidance lives in the index, not here.

Use visual hierarchy and color to direct attention, never as the only carrier
of meaning. Avoid decorative cards, labels, tags, and pills that repeat nearby
text or name a section.

## Review

Present the complete plan as an implementation handoff, organized around the
changes an engineer will make, not the order of the discussion.

Begin with an overview page that makes the outcome, the scope, and the
relationships among the steps clear, and link to each step; use a diagram
when it shows those relationships better than prose. Each step states the
behavior it must produce, its dependencies, exact interfaces, approved
material, and constraints, and how the behavior will be verified. Distinguish
binding requirements from illustrations and unfinished integration, and
automated checks from behavior that needs direct use.

Carry approved wording, code, interfaces, mocks, and prototypes into the
relevant step from the latest revision that showed them, not from the
revision where they were agreed: a mock often changes after the choice that
approved it. Before publishing, open the last revision that rendered each one
and check that the step matches it. Keep approved designs viewable and
interactions usable with their source embedded; a summary, a screenshot, or a link to an earlier
proposal cannot replace the material itself. Before publishing, extract the
preserved source from `plan-data` and check that the plan and the project are
enough to implement and verify the work without earlier revisions or the
conversation.

Resolve implementation-critical unknowns during exploration. If something
genuinely cannot be known until implementation, say why, what must be
investigated, and what result is acceptable. Match the detail to the work; do
not expand routine mechanics to make the plan look thorough.

## Revisions

Show revised material against the version the user reviewed: an exact diff
for text or code, comparable before-and-after views for visuals, with what
changed identified. A short reason may accompany the comparison but does not
replace it.

When a revision records an answer or choice on Agreed, remove that question or
decision from the page in the same revision. Sent items leave the draft when
the next revision lands, so a control that stays looks unanswered and gets
answered again. If the topic is still open, ask the next question, never the
same one.

Preserve earlier revisions so submitted feedback stays attached to what the
user saw. Open the rendered artifact and use it before publishing.
