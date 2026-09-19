# Planning quality

## Exploration

Exploration pages settle open decisions. Do not add an overview page, early
implementation steps, or a summary page. Agreed is the only running
context. It holds the settled decisions, each with a link to the exact
place it came from.

An exploration may address one decision, several connected choices, or a
broad part of the proposal. Keep related parts together when their
interaction matters. Separate them when an unresolved dependency or too
much material would make the proposal hard to assess. Settle the choices
that affect later options before spending time on details those choices
could invalidate.

Resolve routine details from project evidence and settled requirements. Ask
the user about choices that change intended behavior, scope, an interface,
or an important tradeoff. Ask on the page, next to the proposal the choice
affects: a decision component for a selection, a question component for
prose.

When a topic contains a meaningful choice, present a small set of credible
options, recommend one, and show the basis for the recommendation in the
comparison. Do not invent alternatives when only one direction is credible.
Selecting an option must change the nearby proposal, behavior, diagram,
wording, or tradeoff; a row of labeled text blocks is not a comparison. Use
the decision component when a title and one line are enough to judge each
option. Use the visual decision when each option needs a diagram, code, a
chart, or a prototype.

A page starts at the decision. It has no lede, no sentence of rationale,
and no restatement of the question. At most one line of context says what a
mock shows. Each option carries one line of consequence. A sentence that
could sit unchanged on another plan says nothing about this one.

Build each page around the proposal itself. Render or demonstrate the
material when the browser can, and use prose for context or consequences
the page cannot show. Let the content decide the layout. Keep the
recommendation, the evidence and the feedback controls next to the material
they affect, and do not lead with a generic explanation. Choose supplied
components by purpose from the [component index](../components/index.md),
adapt them, or build a plan-local one when the material needs a different
structure. The index holds the guidance for each component.

Use visual hierarchy and color to direct attention, never as the only
carrier of meaning. Do not add decorative cards, labels, tags, or pills that
repeat nearby text or name a section.

## Review

Present the complete plan as an implementation handoff, organized around
the changes an engineer will make, not around the order of the discussion.

Begin with an overview page that makes the outcome, the scope, and the
relationships among the steps clear, and link to each step. Use a diagram
when it shows those relationships better than prose. Each step states the
behavior it must produce, its dependencies, its exact interfaces, the
approved material, the constraints, and how the behavior will be verified.
Say which parts are binding requirements, which are illustrations, and
which are unfinished integration. Say which checks are automated and which
need direct use.

Carry approved wording, code, interfaces, mocks, and prototypes into the
relevant step from the latest revision that showed them, not from the
revision where they were agreed, because a mock often changes after the
choice that approved it. Before publishing, open the last revision that
rendered each one and check that the step matches it. Keep approved designs
viewable and their interactions usable, with the source embedded. A
summary, a screenshot, or a link to an earlier proposal does not replace
the material. Before publishing, extract the preserved source from
`plan-data` and check that the plan and the project are enough to implement
and verify the work without earlier revisions or the conversation.

Resolve implementation-critical unknowns during exploration. If something
cannot be known until implementation, say why, what must be investigated,
and what result is acceptable. Match the detail to the work. Do not expand
routine mechanics to make the plan look thorough.

## Revisions

Show revised material against the version the user reviewed: an exact diff
for text or code, and comparable before-and-after views for visuals, with
the change identified. A short reason may go with the comparison but does
not replace it.

When a revision records an answer or a choice on Agreed, remove that
question or decision from the page in the same revision. Sent items leave
the draft when the next revision lands, so a control that stays looks
unanswered and gets answered again. If the topic is still open, ask the
next question, never the same one.

Preserve earlier revisions so that submitted feedback stays attached to what
the user saw. Open the rendered artifact and use it before publishing.

## Sentences

Check every sentence on every page against this list before publishing.

1. It has a subject and a verb, and it states what a thing is or does. A
   fragment standing in for a claim ("One form.") is not a sentence.
2. It holds one idea. Two half-thoughts joined by a semicolon are two
   sentences.
3. It states the fact instead of hinting at it. "The command overwrites;
   but only a file it wrote" hints. "The command checks first that the
   file is one it built" states.
4. It uses the real name: the function, the file, the command, the number.
   Not "the mark of a built document" but "a script element with id
   `document-data`".
5. A heading or a note title is a label ("Edge labels", "Errors before the
   checks"), not a claim.
6. It has no flourish: no inverted word order, no aphorism, no "found by
   breaking them", no "the way X does".
7. It says something about this plan. A sentence that could sit unchanged on
   another plan says nothing about this one. Cut it.
8. A reader who has never seen the project could restate it as a fact
   about the plan. If they could not, rewrite it.
