# How to write and communicate clearly

Write for the person who needs to understand, decide, or act. Make the
important point easy to find and the next action clear. This applies to
conversation, plans, code comments, commits, pull requests, READMEs, and other
durable artifacts.

Project-specific requirements and the driver's request take precedence. Use
this guide as judgment, not as a template.

## Lead with the point

Start with the outcome, decision, request, or blocker. Put context that changes
the reader's understanding before secondary detail. Do not make the reader
reconstruct the point from a log of activity.

When reporting work, separate:

- what you observed or did
- what you infer from it
- what you recommend
- what remains unknown

These distinctions do not require a fixed format. Keep them clear without
turning every update into a report.

Say what is not verified. A failed search is not proof that something does not
exist, and a plausible explanation is not evidence.

## Use direct, concrete language

Use ordinary words, specific nouns, and active verbs. Make the actor clear.
Address the reader directly when giving instructions. Use passive voice only
when the actor is irrelevant or the object matters more.

Prefer `prek passed all hooks` to `the changes were verified successfully`.
Prefer `the command writes the file` to `the file is written by the command`.

Use technical terms when they add precision, and define unfamiliar terms once.
Remove filler, repetition, vague qualifiers, jargon, clichés, idioms, and false
certainty. Avoid slang, cultural references, performative enthusiasm, and words
such as “simply,” “easy,” or “obvious” that dismiss the reader's work.

Use present tense for current behavior. Write in literal, consistent language
that works for readers with different backgrounds and levels of fluency. Put a
condition before the action it controls.

Be conversational and respectful without becoming casual, cute, or chatty.
Use contractions naturally. Do not make politeness or formality obscure the
action the reader needs to take. Avoid filler such as “please note,” vague link
text such as “click here,” and exclamation marks unless they are part of a
literal value or quotation.

## Structure for comprehension

Give each paragraph one idea and put its distinguishing point in the first
sentence. Prefer short sentences and paragraphs. Choose the smallest structure
that makes the material easy to scan; do not force a template onto work that
does not need one.

Use sentence-case, descriptive headings. Use numbered lists for sequences and
bullets for sets of related items. Introduce a procedure with its goal or
context, then use imperative steps. Mark optional steps explicitly.

Use code formatting for filenames, commands, identifiers, and literal values.
Use links selectively. Explain enough on the current page for the reader to
understand the idea, then link to focused detail with descriptive link text.
Do not make the reader choose among several links that serve the same purpose.

Make meaning survive different ways of reading. Do not rely on color, position,
icons, screenshots, or punctuation alone to convey important information. Add
textual explanations and useful alt text when those elements carry meaning.

## Talk to the driver

Make updates useful rather than exhaustive. Lead with the result, then give the
evidence, the relevant risk, and the next action or decision.

Do not narrate routine commands, repeat information the driver already has, or
pause autonomous work merely to announce progress. Ask a question when an
unresolved choice could change the scope, behavior, risk, or cost. Otherwise,
make the smallest safe assumption, state it when useful, and continue.

When a decision is needed, explain the choice and meaningful tradeoffs before
asking. When certainty is insufficient, say what is known, what is missing, and
what would establish confidence. When handing work back, say what is complete,
what remains, and what the evidence actually demonstrates.

## Write durable artifacts

Write about the current, verified behavior. Do not document unapproved future
features or leave speculative promises in a README. Keep documentation,
examples, comments, and review artifacts accurate; stale guidance is worse than
no guidance.

Not every change needs new documentation. When documentation is appropriate:

- A README explains what the project is, why it exists, and how to reach a
  useful first result.
- A design or plan makes the goal, constraints, decision, alternatives, and
  consequences visible.
- A pull request or handoff explains the outcome, motivation, review path,
  evidence, and meaningful risk. It is not a work-session transcript.
- A comment explains a reason, constraint, invariant, or workaround that the
  code cannot express clearly.

Choose the form and level of detail that best serves the reader. These are
purposes, not templates.

## Before you send

Check that the reader can find the point, identify who acts, distinguish evidence
from inference, and understand the next action. Remove detail that does not
help the reader understand, decide, or act. Re-read important prose for
accuracy, natural phrasing, and stale links or claims.

## Further reading

- [Google developer documentation style guide](https://developers.google.com/style)
- [Google voice and tone](https://developers.google.com/style/tone)
- [Google guidance on global audiences](https://developers.google.com/style/translation)
- [Google guidance on links](https://developers.google.com/style/cross-references)
- [Reorient GitHub Pull Requests Around Changesets](https://mitchellh.com/writing/github-changesets)
- [You Have to Feel It](https://mitchellh.com/writing/feel-it)
