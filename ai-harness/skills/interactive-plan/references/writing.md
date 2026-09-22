# Writing

The reviewer reads a plan page to decide something. Put on the page what
they need to decide it, and nothing else.

Most of that context is short: one line of consequence under an option, a
caption, a heading, a row in a checklist. The reviewer decides from those
lines, so write them to be understood at first reading. When a line needs a
second reading, the reviewer asks about it instead of answering it, and you
lose a round.

## Write this way

Use the real name. Write "`problems()` refuses an option label over 24
characters", not "the build enforces a limit on labels".

Give a reason with every judgment. Write "one Redis cache is the simpler
option" only with the reason attached, as in "because four web processes
read one copy instead of four that fall out of step."

Put one idea in a sentence. Two half-thoughts joined by a semicolon are two
sentences.

A heading and an option's `data-label` name a thing. Make the claim in a
sentence under it. Write "Retry policy", not "Retries are the risk here". A
decision's heading is the question it asks.

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

Fluff: "The trade-off here is real, and it is structural." Strip the names
and the numbers and you have "the X here is real, and it is Y", a form you
could put on any plan. Use that as the test. Strip a factual sentence the
same way and nothing readable remains, because the names and the numbers
were the content. Strip a fluff sentence and you can still read it, because
the form was the content. Delete the second kind rather than rewriting it.
Check the last sentence of a section, the first sentence under a heading,
and every option's line of consequence first, because those are the
positions you are most likely to fill for the sake of filling them.

Em dashes: use a period or a comma.

## When to break a rule

If you would not say a sentence out loud to the reviewer, do not write it,
whatever these rules say. Keep the names, the numbers and the reasons.
