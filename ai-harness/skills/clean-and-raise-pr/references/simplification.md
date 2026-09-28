# Simplification

Simplify after verification, so the tests catch mistakes. Run the project's
checks after every pass. Stop when a pass changes nothing.

The goal is the implementation a reader follows in one pass, not a smaller
diff. Every name, branch and indirection a reader has to hold is a cost the
change has to be worth.

## Remove what the change no longer needs

Delete dead branches, unused parameters and imports, flags nothing sets,
fallbacks for callers that do not exist, and options added for a future
need that has not arrived. Delete debugging output and commented-out code.
Consider inlining a helper with one caller. Do not abstract something that
appears once, and prefer two similar functions over one that takes a
parameter to tell the cases apart.

## Make the code explain itself

Flatten control flow. Return early instead of nesting a condition, and
handle the failure at the top of the function so the body reads as the
normal path. Give each function one job, stated by its name and its
signature. Prefer a function to a class unless the code holds state or
supplies an implementation a caller overrides.

Fail where the assumption breaks. Raise on a missing input at the boundary
instead of carrying a default inward.

Use names and types that say what a thing is or does instead of comments
that say it. Keep a comment that gives a reason the code cannot show: a
constraint, an invariant, a workaround, a surprising decision. Remove a
comment that restates the code or describes how the work was done.

## Follow what is already there

Match the conventions around the change, including the project's own style
guide when it has one. Use the pattern the rest of the file uses, even when
you would introduce a better one here alone. Change only what the work
requires, and leave an unrelated cleanup for its own pull request.

## Read the diff cold

Read the whole diff from top to bottom as if you had never seen it. Look for
leftover print statements, TODOs to resolve or file, outdated comments,
names that differ between files, and anything you would ask about in
review. Fix it now instead of explaining it later.
