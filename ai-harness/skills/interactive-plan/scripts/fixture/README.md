# Build the fixture

The fixture includes every component and figure with realistic content. Use it
to inspect the frame after a change. Build it with
`node scripts/fixture/build.mjs OUT.html`, then publish it to a temporary
session
(`XDG_STATE_HOME=$(mktemp -d) INTERACTIVE_PLAN_PORT=0 node scripts/session.mjs start`),
and open every page in both themes before shipping a frame or component
change.
