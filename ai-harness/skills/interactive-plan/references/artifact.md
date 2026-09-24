# Page source and build

Write one JSON source file for each page in a directory under the system temp
directory. Build it before publishing:

```sh
node scripts/build.mjs PAGE.json PAGE.html
```

The output path must not exist. Build checks structure and writes a
self-contained local preview with an embedded `page-data` record. It changes
no session state. `publish --source DIR` keeps that page's source under
`src/<revision>/<page-id>/`. Do not put generated previews or scratch files
in `DIR`.

Agreed and every other page use the same source shape. Publish Agreed first:

```json
{
  "artifactId": "retry",
  "revision": "1",
  "kind": "exploration",
  "title": "Retry policy",
  "page": {
    "id": "agreed",
    "title": "Agreed so far",
    "agreements": []
  }
}
```

After Agreed, `progress --pages pages.json` fixes this revision's ordered
page IDs and titles. A normal page uses the same outer fields:

```json
{
  "artifactId": "retry",
  "revision": "1",
  "kind": "exploration",
  "title": "Retry policy",
  "page": {
    "id": "policy",
    "title": "Retry policy",
    "file": "policy.html",
    "css": "policy.css",
    "js": "policy.mjs",
    "prototypes": []
  }
}
```

`page.html` may replace `page.file`. Both contain an HTML fragment below the
frame's page title, so do not include an `h1`. Paths are relative to the
source JSON file. CSS, JavaScript, and prototypes belong to the page that
publishes them. The builder embeds their bytes in that page's `page-data`.
The frame and built-in components are pinned when Agreed publishes; another
page cannot change an earlier page's record. The publisher checks assembly
with all pages already ready and checks the complete revision on its last
page.

Page CSS is scoped to `#page-content[data-page-id="ID"]` and remains below
the component cascade layer. Page JavaScript must export
`setup(root, planUI)`. The frame calls it when that page renders. A browser
runtime error may still escape the build check, so inspect novel interactive
pages in a browser before publication.

Page IDs are unique within a revision, not across revisions. The next
revision may use a different page set. Reusing an ID makes a new immutable
record and lets matching unsent draft items carry forward; it never edits
the old record. `agreed` and `feedback` are reserved. A final plan lists
`overview` first after Agreed.

Each published page's HTML is trusted agent-authored markup. Reviewer comments
are plain text. Do not put comments in executable HTML or JavaScript. The
builder escapes literal less-than characters in embedded JSON. Never put the
agent token in a page.
