# Writing

The reviewer uses a plan page to decide what to build. Put the facts, choices,
reasons and consequences on the page. Remove commentary about the page itself.

Most context is short: one line of consequence under an option, a caption, a
heading or a row in a checklist. The reviewer decides from those lines, so
write them for a first reading. If a line needs a second reading, the
reviewer may ask for clarification instead of making the decision.

## Write concrete sentences

Name the actor. Use `is`, `has` or `contains` when one of those words states
the fact plainly. Otherwise use a specific verb. Do not make an abstract idea
carry out an action when the system, agent or user does it.

| Avoid                                       | Write                                                              |
| ------------------------------------------- | ------------------------------------------------------------------ |
| "The answer travels with feedback."         | "Feedback includes the answer under `groups.answers`."             |
| "A checklist arrives with nothing checked." | "Start each checklist with no checked boxes."                      |
| "The revision closes open points."          | "Resolve every open point before publishing the revision."         |
| "The hub wakes you with a submission."      | "The hub sends a wake event when a submission arrives."            |
| "The mock reads as it is."                  | "The component mock renders at its natural width without scaling." |

Use a stronger verb when it names the action: "The frame stores the draft"
is clearer than "The draft is stored" because it names the actor.

Use the real name. Write "`problems()` refuses an option label over 24
characters", not "the build enforces a limit on labels".

Give a reason with every judgment. Write "One Redis cache is simpler because
four web processes read one copy" instead of "One Redis cache is simpler".

Put one idea in a sentence. Two half-thoughts joined by a semicolon are two
sentences.

A heading and an option's `data-label` are labels. Make the claim in a
sentence under the label. Write "Retry policy", not "Retries are the risk here".
Use "Body contents" as a heading, not "What the body carries". In prose,
write "The body contains the request payload."
Use a decision heading for the question the reviewer must answer.

Write so a stranger to the project can repeat any sentence back as a fact
about the plan.

Say each thing once. Do not open a section by restating its heading.

## Avoid these

Personification: "The schema wants a migration before the deploy." Write
"the deploy fails unless the migration runs first."

Metaphor: "The cache is the beating heart of the request path." Write "every
request reads the cache before it reads the database."

Your own care as the subject: "After careful consideration, the retry
belongs in the client." Write "the retry belongs in the client, because the
server cannot tell a dropped response from a dropped request."

A vague word where you have a number: "The endpoint is slow under load."
Write "the endpoint takes 1.9s at 200 requests a second."

A symptom without its cause: "Retries sometimes make the outage worse."
Write "each retry opens a new connection, so a 30-second outage leaves 400
sockets in TIME_WAIT."

Denial: "This is not a rewrite, it is a refactor." Write "the public methods
keep their signatures, and the storage layer changes."

The page describing itself: "The table below compares the three options."
Cut the sentence. The reviewer can see the table.

Fluff: "The trade-off here is real, and it is structural." Delete a sentence
if removing its project names and numbers leaves a generic sentence. Keep it
when those names and numbers carry the meaning. Check the last sentence of a
section, the first sentence under a heading and each option's consequence
first. Those positions often collect filler.

Em dashes: use a period or a comma.

## When to break a rule

If you would not say a sentence out loud to the reviewer, do not write it,
whatever these rules say. Keep the names, the numbers and the reasons.
