# Fixture

Every component and figure with realistic content, for looking at the frame
after a change. Build it with `node scripts/fixture/build.mjs OUT.html`,
publish it to a throwaway session
(`XDG_STATE_HOME=$(mktemp -d) INTERACTIVE_PLAN_PORT=0 node scripts/session.mjs start`),
and look at every page in both themes before shipping a frame or component
change.
