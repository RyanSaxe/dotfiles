# Writing the prose

The reader may never have opened this repository. Write for them, not for
the code's author and not for a reviewer.

## What each part says

The lede is one paragraph. It says what the subject is and what changed,
or what it is made of. A reader who stops after the lede and the opening
figure should be able to say what the subject does.

A node, a heading and a page title name a part by what it does, not by its
file. "The hub" tells a stranger something; "session.mjs" does not until
they have read it. Put the file path on the second line of the node.

A note attaches to the last line of the code it explains. It says what the
code does and why, in one or two sentences. It does not restate the line
under it.

A caption says what the figure shows and, when one matters, the number.

Amber on a node means the subject touched it. In a pull request that is
what changed. In a document about one subsystem it is the parts the
question is about. If there is nothing to mark, mark nothing. Do not use
amber for anything else.

## Which figure to use

A flow is a flowchart. A conversation between parts is a sequence diagram.
A set of modes is a state diagram. A quantity that changes with a parameter
is a chart; add a control when seeing it move is the explanation. A formula
is an equation, usually inline and usually without a control. Prose gives
reasons and consequences; it does not describe what a figure already shows.

## Pages

A page holds one thing a reader can take in at once. A pull request may
need three pages; a subsystem with a model in it may need a dozen, nested
one level deep. A node in a diagram whose id matches a page id opens that
page. Do not put everything on one page because there is little of it, and
do not split a page because it looks long.

## Sentences

Check every sentence against this list before the build.

1. It has a subject and a verb, and it states what a thing is or does. A
   fragment standing in for a claim ("One form.") is not a sentence.
2. It holds one idea. Two half-thoughts joined by a semicolon are two
   sentences.
3. It states the fact instead of hinting at it. "The command overwrites;
   but only a file it wrote" hints. "The command checks first that the
   file is one it built" states.
4. It uses the real name: the function, the file, the command, the number.
   Not "the mark of a built document" but "a script element with id
   `document-data`".
5. A heading or a note title is a label ("Edge labels", "Errors before the
   checks"), not a claim.
6. It has no flourish: no inverted word order, no aphorism, no "found by
   breaking them", no "the way X does".
7. It says something about this repository. A sentence that could appear
   unchanged in a document about another codebase says nothing about this
   one. Cut it.
8. A reader who has never opened the repository could restate it as a fact
   about the code. If they could not, rewrite it.
