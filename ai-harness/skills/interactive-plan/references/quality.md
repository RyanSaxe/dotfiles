# Quality

## Pages

Start a page with its decision or material. Do not add a lede or rationale
before it. Give each option one line of consequence. Delete any sentence
that could sit unchanged on another plan.

People judge a plan by looking. Show the subject and write only what the
page cannot show. Choose the component by what the reviewer must see. The
component index says what each one is for.

Three signs that a page is missing its visual:

- The options differ in something the reviewer could picture, such as a
  layout, a flow, a structure or code, and they are plain decision rows.
  Use a visual decision with a figure in each option.
- The reviewer must judge a change to existing wording, code or an
  interface, and the page describes the change instead of showing the before
  and after. Use the before-after component, not a code block marked as a
  diff.
- A paragraph describes a layout, a flow or an interface that a mock, a
  diagram or the code itself would show.

Where the plan could go more than one credible way, show each way as an
option, recommend one, and show the basis for the recommendation. An
option is a different plan, not a different label. Do not invent an
alternative when only one way is credible.

Resolve routine details from the project and the settled requirements
instead of asking. The user can comment on any text or component without
being asked, so do not add a question that asks what the user thinks of a
proposal. Use a question when the user has context the plan cannot get from
the project, and put it next to the proposal it affects.

Use hierarchy and color to direct attention. When color marks something, say
the same thing in the text. Add no decorative cards, labels, tags or pills
that repeat nearby text.

## Exploration

Each revision should move the plan as far as the reviewer can take it in
one sitting. That is a balance. Too little, and planning takes more rounds
than it needs. Too much, and the reviewer skims, so decisions get made
without being judged. Put the decisions that matter most now in the same
revision, together with the decisions they depend on, and leave for later
what depends on answers not yet given. Some plans take two rounds and others
ten. A page holds one coherent topic and may hold several related decisions.
Agreed is the only running context, so add no overview or summary page.

A decision the reviewer did not answer stays open, unless the submission
says everything else looks good (`groups.alignUnflagged`). Do not repeat an
open decision's unchanged page. Return to it with new evidence, a changed
proposal or a sharper question. When the user asks you to decide, decide,
record the decision on Agreed and continue. When a proposal changes, show
it against the version the reviewer saw. If two revisions in a row resolve
nothing, put what remains on one page with a recommendation for each item.

## The final plan

An engineer or agent who saw none of the revisions and none of the
conversation implements the plan. Anything the plan does not show, they do
not know. Present it when nothing in the task or the work is left to
decide.

Build the plan from Agreed and from everything the conversation and the
feedback settled. Organize it the way the work is best understood, usually
an overview of the outcome and how the parts relate, then pages an
implementer can work from. Each page states the behavior it produces, the
interfaces it depends on and how to verify it.

Reuse the approved material instead of drawing it again or describing it.
Copy the mock, the prototype, the diagram, the code or the wording from its
page source in the session's `src/<revision>/<page-id>/`, and change it to
match everything agreed after it was shown. An earlier mock may have been
approved on one point and rejected on another. Show what was agreed, and say
which parts are binding and which are illustrative.

Before publishing the plan, reread Agreed and the feedback, and check that
every approved item appears in the plan as it was agreed. When
implementation must answer a question, the plan states what it will find
out, how, and what result is acceptable. Match the detail to the work.

## Sentences

Every sentence on every page follows [writing.md](writing.md).
