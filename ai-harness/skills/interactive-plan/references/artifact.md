# Page source and build

Give each page a source directory of its own under the system temp
directory, holding its JSON source and the files it names. Build it to a
path outside that directory before publishing:

```sh
node scripts/build.mjs SRC/policy/policy.json OUT/policy.html
```

The build refuses to overwrite, so build a change to a new path or delete
the old output first. `publish --source SRC/policy` keeps that directory
under `src/<revision>/<page-id>/` in the session, so keep built pages,
previews and scratch files out of it. Embed every local resource a page
uses. Do not install packages to author a plan.

A revision changes its pages, their CSS, JavaScript and prototypes, and
Agreed. The frame, the skill's components, the helper and the hub are skill
code. If feedback asks to change one of them, say so in the chat and plan it
as skill work.

Agreed and every other page share the outer fields. Agreed also requires a
`task`, whose fields are in [agreements.md](agreements.md):

```json
{
  "artifactId": "retry",
  "revision": "1",
  "kind": "exploration",
  "title": "Retry policy",
  "page": {
    "id": "agreed",
    "title": "Agreed so far",
    "task": {
      "title": "Retry policy",
      "html": "<p>Checkout retries a failed charge once, so a brief gateway outage costs one slow request instead of a failed order.</p>"
    },
    "agreements": []
  }
}
```

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

| Field      | Contract                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------- |
| artifactId | Stable ID for the whole session, using letters, digits, underscores or hyphens.                |
| revision   | The same value on every page of a revision, and a new value for each revision: `"1"`, `"2"`.   |
| kind       | `exploration` for proposals, `plan` for the complete final handoff.                            |
| title      | The plan's title.                                                                              |
| page.file  | An HTML fragment, relative to the JSON file. `page.html` may hold the fragment inline instead. |
| page.css   | Optional page CSS. The frame scopes it to this page.                                           |
| page.js    | Optional module that exports `setup(root, planUI)`.                                            |
| prototypes | Optional prototypes for this page. See [prototypes.md](prototypes.md).                         |

Page IDs are unique within a revision. Reusing a page ID in a later
revision lets the reviewer's unsent draft on that page carry forward. `agreed`
is only for the Agreed page, and `feedback` is reserved. A final plan lists
`overview` first after Agreed.

Page HTML is trusted markup written by the agent. Reviewer comments are
plain text. Never put them into executable HTML or JavaScript, and never put
the agent token in a page.
