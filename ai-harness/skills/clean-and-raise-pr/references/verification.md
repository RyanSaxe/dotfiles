# Verification

A passing test suite does not show that the change works where a person
uses it. Verification does.

## Run what the project has

Find the project's own checks and run all of them: a pre-commit
configuration, a Makefile or task runner target, package scripts, a CI
workflow, the validation section of the README. They define what passing
means for this repository. Do not add a checker to a project that has none.
Say in the brief that there are no checks and verify by hand.

## Use the real interface

Start from what the user asked for, not from the files that changed. Run the
command, open the UI, load the configuration with the program that reads it,
call the library as a caller would. Check the intended result and the side
effects. For a bug fix, reproduce the failure first, then show the same path
succeeding. For documentation or a skill, using it means following it on a
real task.

A small, familiar change needs one direct check. A new, visual, stateful, or
high-risk one needs realistic use: alternate paths, repeated actions, and
transitions that could expose hidden state. When you cannot use the change
directly, use the closest realistic substitute and say what it does not
prove.

## Audit the tests

Read the tests that cover the changed behavior as if reviewing them.

A test is worth keeping when it fails if the behavior breaks and survives a
refactor that keeps the behavior. Both halves matter. A test that reaches
into a private call sequence, or that pins a string, a format or generated
output nobody promised, breaks on a rewrite that changed nothing and passes
while the behavior rots.

Test the interface a caller uses, at the smallest level that proves the
contract without replacing the real thing with a mock. Cover the smallest
set of cases that separates the intended behavior from a plausible mistake.
A test whose assertion is not obvious from reading it is a test to rewrite.

Delete a test that is not worth keeping, and say why in the commit that
removes it. Do not add a test because a file changed.

When the change is documentation or configuration and the project has no
test for it, the project's validators are its tests, and the body says how
the document was used instead.

Never delete, skip, or weaken a failing test to make the checks pass. A
failing test means a bug in the change or in the test. Fix whichever it is.

## Simulate a user

Give a subagent only what a new user would have: the interface and the task
the feature is for. Ask it to do the task and report what broke, what
confused it, and what it expected instead. It must not read the diff or the
implementation first. If the harness has no subagent, do this yourself:
close the implementation and follow only the documentation or the visible
interface. Verify each finding in its report before acting on it.
