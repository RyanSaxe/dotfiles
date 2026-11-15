# Verification

Passing tests are the first check, not the last. Before you call a change
done, use it where a person will actually meet it, and see it work there.
Take the shortest path to evidence that convinces you, and stop when you
have it. Then share that evidence wherever the change is discussed, like a
pull request's description, because it's what will convince the reader too.

## Use it through its real interface

Run the command, open the page, load the config in the program that reads
it, or call the library the way another project would. Do it on a throwaway
instance with its own socket or folder, never on one the user is running.

## Match the effort to the change

A small, familiar change needs one direct confirmation. A normal feature
needs its intended path and its most important failure. A new, visual or
stateful change needs realistic use, with repeated actions and the
transitions that could expose hidden state. Stay with what a real user would
do, and don't count a failure in a situation nobody would reach as a bug.

## Reproduce a bug before and after

For a bug, make it happen first, through the interface where it showed up.
After the fix, the same steps should work.

## Compare with the intended behavior

A surprise isn't a bug until you've reproduced it and compared it with what
was intended. Learn the intent from the request, the docs or the user, never
from the code, which may be what's wrong. When the intent isn't clear, ask
before you change anything.

## Look at anything visual

Take a screenshot and look at it. Check a web page at 390, 768 and 1280
pixels wide, and record motion as timed screenshots, because a screencast
drops frames.
