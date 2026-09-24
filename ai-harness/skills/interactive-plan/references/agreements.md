# Agreements

| Field       | Contract                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------- |
| id          | Unique stable agreement ID, preserved when the topic changes.                                |
| title, html | Concise title and the actual agreement, with exact details as needed.                        |
| state       | agreed by default. reopened retains prior wording until resolved. retired includes a reason. |
| change      | Optional marker for this publication only: `new` or `updated`.                               |
| sourceRefs  | References to choices, notes, answers or conversation context that support the agreement.    |
| source      | Plain source text when no feedback item can be referenced.                                   |

Each agreement needs `sourceRefs` or `source`. If an aligned submission has
no choice, note or answer for a settled decision, name its revision and
submission ID in `source`, state that `groups.alignUnflagged` was true, and
explain why the comments did not challenge that decision.

Each reference has a `kind`:

| kind         | Required fields        | Meaning                                                                              |
| ------------ | ---------------------- | ------------------------------------------------------------------------------------ |
| note         | submissionId, noteId   | A saved comment, with its quote and target.                                          |
| choice       | submissionId, choiceId | A saved choice. choiceId is its key under `groups.choices`, such as `page/decision`. |
| answer       | submissionId, answerId | A saved answer to a question component. answerId is the submission's answers key.    |
| conversation | text                   | Context from the agent conversation, labeled as such.                                |

When Agreed publishes, the publisher resolves each browser reference against
this session's saved submissions before that page becomes visible. It embeds
the exact text and location as `sourceRecords` and rejects a missing
submission or item. Do not write
`sourceRecords` yourself. Remove old `change` markers on the next
publication, and do not recreate settled entries to fill the record.

The Agreed page renders each agreement as a card: the decision, then a strip
naming the revision and the note, choice, or answer it came from, with
Preview and Open buttons. Preview expands that revision's page inside the
card, scrolled to the source and highlighted. Open shows the revision
read-only. Further sources sit behind a count on the strip.

The strip, Preview, and Open use the first browser source in `sourceRefs`.
If agreed material changes in a later revision, update the agreement: mark
it `change: updated`, rewrite its text, and put the newest source first.
Otherwise Preview opens the old version.

A valid source does not make the summary correct. Read the feedback and the
conversation before writing or changing an agreement. A comment the user
leaves on a card records the agreement's ID and changes nothing on its own.
