# Documentation

Not every change needs documentation. Every document the change makes wrong
needs fixing, and every reader the change affects needs somewhere to learn
about it. Decide based on the reader, not on the diff.

## Decide what the change needs

Ask who has to know about this change and where they would look.

- A new command, flag, option, or configuration key needs usage
  documentation where the project keeps it: README, a docs directory, a man
  page, `--help` output.
- A changed default, changed behavior, or removed option needs the same,
  plus a changelog entry when the project keeps one.
- A public function or type needs a doc comment where the name and the
  signature leave something unsaid. A typed `euclidean_distance(a, b)`
  needs none. Follow what the project already does: many projects treat a
  docstring on a self-evident function as noise.
- A non-obvious decision, constraint, or workaround needs a code comment
  where a reader would otherwise be surprised.
- An internal refactor with no visible change usually needs nothing.

When the brief said no docs were needed and this phase finds otherwise, add
them; do not ask again.

## Find what the change made wrong

The diff shows what changed, not what it made wrong. Search the docs,
comments, examples, and sample configurations for every name, flag,
default, path, and behavior the change touched, including files the diff
did not open. Fix each one. A document that describes the old behavior is
worse than none, because readers trust it.

## Write for the reader

- Start with what the reader can do or must know. Explain how it works
  after that.
- Describe current behavior in the present tense. Do not describe the change
  ("previously", "now supports") or how it was built; that belongs in the
  commit message and the pull request.
- Write each fact in one place and link to it from elsewhere. Copies go out
  of date.
- Follow the project's existing structure, headings, and tone, and its
  style guide when it has one. Add to the document readers already use
  before creating a new one.
- Every example must run. Run it and paste the real output.
- Do not document unfinished work or promise future features.

## Verify the docs

Run every example you wrote or changed. When verification used a user
simulation, that user reads only the documentation; a task it could not
finish from the docs is a documentation bug, even if the code works. If
this phase changes a document the simulation read, run the simulation
again.

Put documentation in the commit that adds the behavior it describes. The
history rebuild puts them together.
