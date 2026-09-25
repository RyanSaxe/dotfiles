# Agreements

## The task

The Agreed source has a required `task`: what the plan is building towards,
as the agent currently understands it, in a title and two or three
sentences. Say what will exist when the work is done and why, and what is
deliberately left out when that matters. Decisions follow it on Agreed, and
open questions belong on pages, so neither goes in it.

State it in revision 1 from the conversation, and revise it whenever
feedback changes what is being built. The reviewer reads it and comments
when it is wrong. Never ask the reviewer to approve it.

| Field  | Contract                                                        |
| ------ | --------------------------------------------------------------- |
| title  | What is being built, in a few words.                            |
| html   | Two or three sentences: the outcome, why, and what is left out. |
| change | Optional marker for this publication only: `new` or `updated`.  |

## Decisions

| Field       | Contract                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------- |
| id          | Unique stable agreement ID, preserved when the topic changes.                                |
| title, html | Concise title and the actual agreement, with exact details as needed.                        |
| state       | agreed by default. reopened retains prior wording until resolved. retired includes a reason. |
| change      | Optional marker for this publication only: `new` or `updated`.                               |
| sourceRefs  | References to choices, notes, answers or conversation context that support the agreement.    |
| source      | Plain source text when no feedback item can be referenced.                                   |

Each agreement needs `sourceRefs` or `source`. When `groups.alignUnflagged`
settled a proposal the page stated, name the revision and submission ID in
`source`, state that `groups.alignUnflagged` was true, and explain why the
comments did not challenge it.

Each reference has a `kind`:

| kind         | Required fields        | Meaning                                                                              |
| ------------ | ---------------------- | ------------------------------------------------------------------------------------ |
| note         | submissionId, noteId   | A saved comment, with its quote and target.                                          |
| choice       | submissionId, choiceId | A saved choice. choiceId is its key under `groups.choices`, such as `page/decision`. |
| answer       | submissionId, answerId | A saved answer to a question component. answerId is the submission's answers key.    |
| conversation | text                   | Context from the agent conversation, labeled as such.                                |

When Agreed publishes, the publisher resolves each browser reference against
this session's saved submissions and rejects a missing submission or item.
Do not write `sourceRecords` yourself. Remove old `change` markers on the
next publication, and do not recreate settled entries to fill the record.

When the agreement settles something the reader saw, such as a look, a
layout, wording or an interface, its `html` names the material that shows
it: the revision, the page and the figure, prototype or code block. The
final plan reuses that material, updated to match later agreements.

The reader's Preview of an agreement opens the first browser source in
`sourceRefs`. When agreed material changes in a later revision, mark the
agreement `change: updated`, rewrite its text, and put the newest source
first.

A valid source does not make the summary correct. Read the feedback and the
conversation before writing or changing an agreement. A comment the user
leaves on an agreement records the agreement's ID and changes nothing on its
own.
