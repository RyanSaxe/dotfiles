# Build the fixture

The fixture includes every component and figure with realistic content. The
builder bundles whatever `components/` holds, so adding a directory there is
all it takes for the fixture to render it. Build it with
`node scripts/fixture/build.mjs OUT.html`, then publish it to a temporary
session
(`XDG_STATE_HOME=$(mktemp -d) INTERACTIVE_PLAN_PORT=0 node scripts/session.mjs start`),
and open every page in both themes before shipping a frame or component
change.

The `slots` page holds each component slot against a `<pre>`, a `<div>`, a
captioned figure, a table, a blockquote and a paragraph. The space above a
block and the space below it should match in every cell, at a wide window
and at 375px.
