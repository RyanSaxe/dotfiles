# Artifact format

Write HTML pages and a JSON manifest in a directory of your own under the
system temp directory, with custom CSS and JavaScript when a page needs
them, and build one artifact from them there:

```sh
node scripts/build.mjs SOURCE.json ARTIFACT.html
```

The output filename must not exist yet. Use the temp directory for scratch
files. A sandbox can write there. `publish --source DIR` copies the source to
`src/<revision>/` inside the session, and the next round starts from that
copy. The publisher writes artifacts to `artifacts/` and refuses a revision
that already exists there. The builder puts the frame and the authored
content into one HTML file. It does not bundle
imports or linked files, so embed every local resource the plan needs. Do
not install packages to author a plan.

A revision can change the plan's pages, its CSS and JavaScript, its
prototypes and Agreed. A request to redesign the look applies to those parts.
The frame, the skill's components, the helper and the hub are skill code. If
feedback requests a change to one of them, say so in the chat and plan it as
skill work.

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

The embedded `plan-data` JSON contains the page HTML, agreement records and
prototype source. Page HTML is trusted markup written by the agent,
not Markdown. User comments are plain text. Never put them into executable
HTML or JavaScript. The builder escapes literal less-than characters in the
embedded JSON, and that escaping stays if you edit an assembled artifact.
Leave `session-config` empty for the publisher to fill, and never put the
agent token in the page.
