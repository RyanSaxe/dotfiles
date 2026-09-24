# Quality

## Pages

Start a page with its decision or material. Do not add a lede or rationale
before it. Give each option one line of consequence. Delete any sentence
that could sit unchanged on another plan.

Where the plan could go more than one credible way, show each way as an
option, recommend one, and show the basis for the recommendation. An
option is a different plan, not a different label. Do not invent an
alternative when only one way is credible. The component index says what
each component is for.

Build each page around the proposal. Choose components by what the reviewer
needs to see. For architecture choices, show boundaries or data flow when
those differ. Put costs and risks side by side when they distinguish the
options. Where the browser can show material,
rendered, drawn or demonstrated, show it, and use prose for the context and
consequences the page cannot show. Do not restyle a component: the
builder puts component CSS in a layer above the plan's, so the rule is
ignored rather than half-applied. A component is as wide as the reading
column. Resolve routine details from
the project and the settled requirements instead of asking.

The user can comment on any text or component without being asked, so do not
add a question that asks what the user thinks of a proposal. Use a question
when the user has context the plan cannot get from the project. Put that
question next to the proposal it affects. Give a question with no related
proposal its own page.

Use hierarchy and color to direct attention. When color marks something, say
the same thing in the text. Add no decorative cards, labels, tags or pills
that repeat nearby text.

## Exploration

Use one exploration page per decision that needs review in this round. Do not
add an overview, summary or early implementation page. Use Agreed as the only
running context. Put related new or changed points in one revision so the
reviewer can settle them in one round. Do not repeat an unchanged page because
the reviewer did not answer it. Keep that decision open and return with new
evidence, a changed proposal, or a sharper question.

Assemble the final plan from Agreed. A decision that is not on Agreed is not
settled and cannot bind a step. Resolve decisions needed for the final plan
before presenting it.
When the user asks you to decide, decide, record the decision on Agreed and
continue. When implementation must answer a question, state what it will
find out, how it will find out and what result is acceptable. If two
revisions in a row resolve nothing, present the plan with its remaining open
items named.

## Review

Present the complete plan as a handoff organized around the changes an
engineer will make. Start with an overview page that states the outcome,
scope and relationships among the steps. Link it to one page per step. Each
step states the behavior it must produce, its dependencies, exact interfaces,
approved material, constraints and verification method. Each step also
identifies the binding parts, illustrative parts and automated checks.

Carry approved wording, code, interfaces and mocks into the step from the
latest revision that showed them, embedded, not summarized or linked. The
plan and the project must be enough to implement and verify the work
without earlier revisions or the conversation. Say why an unknown must wait
for implementation, what to investigate, and what result is acceptable.
Match the detail to the work.

## Iterating

When a proposal changes between revisions, show the change against what the
user reviewed: a diff for text and code, before and after for visuals.
Unannotated wording can stay in a revised proposal, but silence does not
settle its central decision. Remove a decision or question after recording
its answer on Agreed. If a control remains, the next revision asks the
question again. If the topic is still open, bring back new material or ask a
sharper question, never the same one.

## Sentences

Every sentence on every page follows [writing.md](writing.md).
