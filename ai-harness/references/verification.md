# Verification

Passing tests and CI don't show that a change works. Before you call it
done, use it the way the people who rely on it would, and see that it does
what they need.

## Use it the way its users would

Start from what the user asked for, not from the files that changed. Think
about who will meet the change, and try what each of them would try, through
the same interface and with only what they would know. Different people find
different problems.

Cover the ordinary path first, then the mistakes and interruptions a real
user would make. For a large or risky change, give the attempts to fresh
agents. Brief each one on who they are and what they want, and leave out
what you suspect. They report what they did and what they saw, and you judge
it.

## Compare with the intended behavior

A surprise isn't a bug until you've reproduced it on the same revision and
compared it with the intended behavior. Learn what was intended from the
request, the docs or the user, not from the code, because the code may be
what's wrong, and behavior that looks wrong may be what someone asked for.
When the intent isn't clear, ask before you change anything.

Keep defects apart from friction and from problems with the environment.
For a confirmed bug, fix the cause, add the regression test `testing.md`
describes, and repeat the attempt that found it.

## Match the effort to the change

A wording change needs one look where it renders. A normal feature needs its
main path and its most important failure. A new, visual or stateful change
needs realistic use from several angles.

## Look at the real thing

Behavior, rendering and keys need the real program, so open it and use what
you changed. For anything visual, take a screenshot and look at it. Check a
web page at 390, 768 and 1280 pixels wide, and record motion as timed
screenshots, because a screencast drops frames. Try it on a throwaway
instance with its own socket or folder, never on one the user is running.
When you hand the work back, say what you ran and what you saw, and attach
the screenshot.
