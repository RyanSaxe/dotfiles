# What a good document says

The reader may never have opened this repository. Everything on the page
is for them, not for the code's author and not for a reviewer.

## Start with what moved, or what is there

The lede is one paragraph that says what the subject is and what changed
or what it is made of. A reader who stops after the lede and the opening
figure should be able to say what the subject does. If they cannot, the
lede is not finished.

## Name parts by what they do

A node, a heading and a page are named for the job a part does, not for
where its file lives. "The hub" and "the working card" tell a stranger
something. "session.mjs" tells them nothing until they have read it, and
the point of the document is that they have not. The file path goes on the
second line of the node, not in its name.

## Quote the code; do not retype it

An excerpt is read from the repository by the build. Point it at the file
and the lines and write the notes; the lines arrive on their own. A note
attaches to the last line of what it explains, says why the code is the way
it is, and stops. A note that paraphrases the line under it is noise.

## Mark what the subject touched and nothing else

Amber means the subject touched this. In a pull request it is what
changed. In a question about one subsystem it is the parts the question is
about. In a repository with nothing to mark, nothing is marked and the
diagram is the system on its own. A mark that means something else in one
document and something different in the next has stopped meaning anything.

## Choose the material for the idea

A flow is a flowchart. A conversation between parts is a sequence. A set
of modes is a state diagram. A thing that varies with a parameter is a
chart, and if seeing it move is the explanation, give it a control. A
formula is an equation, usually inline, usually with nothing to drag. Prose
carries the reasons and the consequences; it does not describe what a
figure already shows.

## Break a complicated subject into pages

A page holds one thing a reader can take in at once. A pull request may be
three pages; a subsystem with a model in it may be a dozen, nested one
level. A node in a diagram that names a page opens it, so a reader moves
from the drawing into the part they want. Do not put everything on one
page because there is not much of it; do not split a page because it looks
long.

## Say nothing you would say about any repository

A sentence that could sit unchanged in a document about a different
codebase says nothing about this one. Cut it. The same for a heading that
names a section instead of saying what is in it, and for a caption that
repeats the prose above the figure.
