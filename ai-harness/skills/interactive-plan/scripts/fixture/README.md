# Build the fixture

The fixture includes every component and figure with realistic content. The
builder bundles whatever `components/` holds, so adding a directory there is
all it takes for the fixture to render it. From the skill directory, build
and open a standalone preview:

```sh
fixture_dir=$(mktemp -d)
node scripts/fixture/build.mjs "$fixture_dir/fixture.html"
open "$fixture_dir/fixture.html"
```

On Linux, use `xdg-open` instead of `open`. This assembled fixture has several
pages but no `page-data` record,
so the page-only `session.mjs publish` command rejects it. Inspect every page
in both themes before shipping a frame or component change. The standalone
preview does not send feedback to a session.

The `slots` page holds each component slot against a `<pre>`, a `<div>`, a
captioned figure, a table, a blockquote and a paragraph. The space above a
block and the space below it should match in every cell, at a wide window
and at 375px.
