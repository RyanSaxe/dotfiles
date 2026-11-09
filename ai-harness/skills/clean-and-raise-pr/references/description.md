# Pull request description

A body states what the change is, why it matters, how to review it, and
what was checked. It is not a log of the work.

## Title

Write the title in the repository's commit subject style. When the series
is one commit, use that commit's subject. Otherwise write one subject for
the whole change, not a list of what it contains.

## The parts

A reviewer opens a pull request to answer two questions the diff cannot
answer: should this change exist, and does it do what its author meant. The
names, the comments and the structure they read off the code. The body
answers those two.

Length follows the change and not a target. A three-line fix with a cause
nobody would guess can take a paragraph, and a large mechanical change can
take two sentences.

**What it does.** No header. What someone can do after this change,
described the way a person using it would describe it, and what happened
before. Where something was going wrong, say what it was, because a
reviewer who can see the problem can judge whether this is the right fix.
Use a code block or a diagram where it shows a main interface, the
structure, or the logic faster than a paragraph would. Link the issue or
discussion if there is one.

**Commits.** A table with four columns: `#`, the commit subject without its
prefix, the measured line count from the rebuild, and what to check. The
last column says what the commit does and the one thing the reviewer should
verify in it. A cell may hold an example or a code block when that shows
the work better than a sentence.

**Checked.** What you did with the change and what happened, beyond what CI
and the tests already show. CI reports the checks and the diff carries the
tests, so neither belongs here. When the result is visual, the screenshots
are the check. Say what each one shows, and give the reasoning or the
numbers where they change what the reviewer concludes. Only what was run in
this repository on this branch.

**Design.** Optional, and last. Where the change took one path over another
and the choice was not obvious, say which way you went, what you turned
down, and what that cost. Most pull requests have nothing to put here, and
an empty section is worse than none.

Nothing else. For a one-commit pull request, the title is the commit
subject and the body is the first part plus Checked.

## Rules

- Write the body to a file and pass it with `--body-file`. Do not write it
  inline in a shell command.
- Every claim says what was run or used. "Tested locally" is not a claim.
- Reference each image in the body as a Markdown image with its local path,
  then pass the same path to `--attach '<path>#<alt text>'` on
  `gh pr create` or `gh pr edit`. gh uploads it and rewrites the reference.
  A referenced image that is not attached renders broken.
- Link only what the reader can open. A path on your own disk is a dead
  link in a pull request.
- After `gh pr create` or `gh pr edit`, read the body back with
  `gh pr view --json body` and check that no image reference still points at
  a local path. gh keeps a pull request whose attachments partly failed,
  which leaves the ones that failed as broken images. Re-run `gh pr edit`
  with those paths.
- Add a review comment of your own only as a last resort, for one hunk whose
  reason fits neither in the code nor in the commit message.
