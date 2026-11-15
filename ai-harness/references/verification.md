# Verification

Passing tests and CI don't show that a change works. Before you call it
done, use it the way its users would.

## Use it as its users would

Start from what was asked for, not from the files that changed. Use the
change through the interface its users have, knowing only what they would
know. Try the normal path first, then the mistakes and interruptions a real
user would make.

## Scale it to the change

A small change that's easy to undo needs one realistic use. A large, risky
or user-facing change needs several simulated users with different
backgrounds and goals. Give each one a fresh context and a brief that says
who they are and what they want, and leave out what you suspect. They report
what they did and what they saw, and you judge it.

## Compare with the intended behavior

A surprise isn't a bug until you've reproduced it on the same revision and
compared it with the intended behavior. Learn what was intended from the
request, the docs or the user, not from the code, because the code may be
what's wrong, and behavior that looks wrong may be what someone asked for.
When the intent isn't clear, ask before you change anything. For a confirmed
bug, fix the cause and repeat the attempt that found it.

## Look at the real thing

Behavior, rendering and keys need the real program. For anything visual,
take a screenshot and look at it. Check a web page at 390, 768 and 1280
pixels wide, and record motion as timed screenshots, because a screencast
drops frames. Use a throwaway instance with its own socket or folder, never
one the user is running.
