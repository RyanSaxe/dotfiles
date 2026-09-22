# Simplification

Simplify after verification, so the tests catch mistakes. Run the project's
checks after every pass. Stop when a pass changes nothing.

## Remove what the change no longer needs

Delete dead branches, unused parameters and imports, flags nothing sets,
fallbacks for callers that do not exist, and options added for a future
need that has not arrived. Delete debugging output and commented-out code.
Consider inlining a helper with one caller. Do not abstract something that
appears once.

## Make the code explain itself

Use names that say what a thing is or does instead of comments that say it.
Flatten control flow: return early instead of nesting conditions, write one
plain loop instead of chained calls, write a straight sequence instead of a
callback chain. Give each function one job, stated by its name.

Keep comments that give a reason the code cannot show: a constraint, an
invariant, a workaround, a surprising decision. Remove comments that restate
the code or describe how the work was done.

## Keep the change small

Change only what the work requires. Follow the conventions around the
change instead of adding new ones. Do not add an unrelated cleanup to this
pull request; suggest it for its own.

## Read the diff cold

Read the whole diff from top to bottom as if you had never seen it. Look for
leftover print statements, TODOs to resolve or file, outdated comments,
names that differ between files, and anything you would ask about in
review. Fix it now instead of explaining it later.
