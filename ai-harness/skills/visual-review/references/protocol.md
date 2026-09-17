# Protocol

The browser asks; you answer with an outline and then pages. The browser polls
metadata only and fetches page content separately, so progress is visible
without anything streaming.

## Events you receive

`wait` returns one event.

| Field     | Meaning                                                           |
| --------- | ----------------------------------------------------------------- |
| `id`      | The event id. For a new question this is also the question id.    |
| `kind`    | Always `ask`. A picked choice arrives as an ask naming its block. |
| `payload` | `{ id, text, context }`.                                          |

`context` is one of:

- `null` — a new question.
- `{ questionId, pageId, quote? }` — a follow-up from a page, with the
  highlighted text when there was one.
- `{ questionId?, file, ref, lines: [start, end] }` — a question about lines
  selected in the code pane.
- `{ questionId, pageId, blockId }` — a choice the reader picked; the text is
  the option.

A follow-up carrying a `questionId` belongs to that question. Decide whether it
becomes a section wrapped in `::: added` on the page it came from, or a new page
through `plan --append`. Do not rewrite pages the reader has already read.

## Commands you run

| Command                                                                  | Effect                                                                                                                                     |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `wait [--timeout S]`                                                     | The next unacknowledged event, or `{ waiting: true }` at the timeout. A timeout is not completion.                                         |
| `ack --id EVENT`                                                         | Marks the event read. Idempotent.                                                                                                          |
| `plan --question QID --title "…" --pages "id=Title,id=Title" [--append]` | Declares the outline. Page ids match `^[a-z0-9][a-z0-9-]{0,39}$`. A title may contain a comma; the split happens only where an id follows. |
| `status --question QID --text "reading 14 files"`                        | One line under the progress bar. Replaces the previous line.                                                                               |
| `page --question QID --id PID --file page.md`                            | Publishes Markdown for a planned page. Publishing again replaces it and marks it updated, keeping the reader's place.                      |
| `done --question QID`                                                    | Marks the answer complete. Planned pages that were never written leave the outline.                                                        |
| `export [--out FILE]`                                                    | Writes the whole session as one HTML file.                                                                                                 |
| `state`                                                                  | The state the browser polls.                                                                                                               |

Replanning without `--append` may rename, reorder, or replace any page nobody
has read. A page you already published stays, because the reader may be on it.

## The state the browser polls

```json
{
  "sessionId": "…",
  "stage": "ready | working",
  "repo": { "name": "acme/payments", "ref": "main", "root": "/…" },
  "questions": [
    {
      "id": "ask-event-id",
      "title": "Payments architecture",
      "text": "I want to understand the architecture…",
      "status": "asked | planned | writing | done",
      "statusLine": "reading 14 files",
      "askedAt": "2026-09-17T21:03:00Z",
      "context": null,
      "followUps": [],
      "pages": [
        {
          "id": "overview",
          "title": "Overview map",
          "status": "written",
          "revision": 1
        },
        { "id": "abstractions", "title": "Abstractions", "status": "planned" }
      ]
    }
  ],
  "pending": 0
}
```

Page content is fetched separately. A page whose `revision` is above one has
been rewritten since the reader first saw it, and the outline marks it.

Several questions may be in flight, each with its own progress. Answer them in
order unless a later one is a follow-up to the one you are writing.

## Reading the repository

The browser reads the repository through the helper, and so can you, but the
helper is not your only access. Use your own tools to read code; use these
routes when you want to know what the reader can see: `/repo/file`,
`/repo/tree`, `/repo/paths`, `/repo/diff`, `/repo/exists`. A path you name in a
page must exist at its ref, or the chip will not appear.
