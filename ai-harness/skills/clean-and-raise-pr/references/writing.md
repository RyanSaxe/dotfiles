# Writing

Everything this skill writes is read by someone who has to decide
something. A reviewer decides whether to approve. A maintainer a year from
now reads a commit message to find out why a line is there. Write for that
person.

## How it reads

Write English you would say out loud to the reviewer. "Opening a file at a
cited reference used to start at line 1, and the reader scrolled to find
the lines" is something you would say. "`renderRange` takes a zero-based
start" is not, and it belongs in a commit message or a comment in the code.

Give the number where you have one. "14 of the 25 blocks produced a name
nobody could read" tells the reviewer how bad it was. "Most blocks had
naming problems" does not.

Say a thing once. The title, the body, the commit messages and the code
each say something different. Repeating one inside another is how a body
grows until reading it costs more than reviewing the change.

## Leave out

An abstraction doing what a person does. "The contract stopped there."
Nobody wrote it down.

A claim that the change matters, with nothing behind it. "This is the part
that decides whether the feature is usable."

A line written to land well. "One of them was nothing but CSS." Strip the
names and the numbers out of a sentence and read what is left. A sentence
about the change falls apart, because the names and the numbers were the
content. A sentence written for effect survives, because the shape was the
content. Delete the second kind. Look first at the last sentence of a
paragraph and the first sentence under a heading.

Anything the reader cannot open. A path on your own machine, a script you
ran and did not commit, a file that exists only where you work.

Writing that describes itself. "The table below lists the commits."

Em dashes. Use a period or a comma.

## When to break a rule

If you would not say a sentence out loud to the reviewer, do not write it,
whatever these rules say. Keep the problem, the behaviour, the reasons and
the numbers.
