# The artifact

Write HTML pages and a JSON manifest in a directory of your own under the
system temp directory, with custom CSS and JavaScript when a page needs
them, and build one artifact from them there:

```sh
node scripts/build.mjs SOURCE.json ARTIFACT.html
```

The output filename must not exist yet. The temp directory is scratch: a
sandbox can always write it, and `publish --source DIR` keeps a copy of it
as `src/<revision>/` inside the session, which is where the next round
starts. The publisher owns `artifacts/` and refuses a revision that already
exists there. The builder puts the frame and the authored content into one
HTML file. It does not bundle
imports or linked files, so embed every local resource the plan needs. Do
not install packages to author a plan.

A revision changes the plan's pages, its own CSS and JavaScript, its
prototypes, and Agreed, and a request to redesign the look means those. The
frame, the components in the skill, the helper, and the hub belong to the
skill. When feedback asks for a change to one of them, say so in the chat
and plan it as skill work.

## Manifest

| Field      | Contract                                                                                                   |
| ---------- | ---------------------------------------------------------------------------------------------------------- |
| artifactId | Stable artifact ID, using letters, digits, underscores, or hyphens.                                        |
| revision   | New value for each publication. Periods are allowed.                                                       |
| kind       | exploration for proposals. plan for the complete final handoff.                                            |
| title      | Human-readable artifact title, shown once at the top of the sidebar.                                       |
| pages      | Ordered records with unique id, title, and html, or file instead of html: a path relative to the manifest. |
| css, js    | Optional paths to custom files, relative to the manifest.                                                  |
| agreements | Optional structured agreement records.                                                                     |
| prototypes | Optional preserved, self-contained interactive documents.                                                  |

A final plan begins with the page ID `overview`. The remaining pages are
the implementation steps. The ID `feedback` is reserved, and `agreed` is
reserved when the manifest has agreements. Keep page IDs the same across
revisions: unsent draft items carry over to the next revision by page ID
and anchor.

The embedded `plan-data` JSON holds the page HTML, the agreement records,
and the prototype source. Page HTML is trusted markup written by the agent,
not Markdown. User comments are plain text. Never put them into executable
HTML or JavaScript. The builder escapes literal less-than characters in the
embedded JSON, and that escaping stays if you edit an assembled artifact.
Leave `session-config` empty for the publisher to fill, and never put the
agent token in the page.
