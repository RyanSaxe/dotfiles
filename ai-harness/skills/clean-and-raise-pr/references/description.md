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

## Example

```markdown
feat(visual-review): open a referenced file on the cited lines

Clicking a reference such as `src/session.py:345-357` opens the file in the code pane at lines 345–357. The lines above and below are collapsed into two fold bars. Each bar shows the name of the function or class it hides and expands by 60 lines per click. Notes on the file appear as numbered markers in the gutter. Clicking one opens the note. Selecting lines and pressing `a` adds `path:start-end` to the question composer.

Before this change the pane opened at line 1 and the reader scrolled to the cited lines by hand.

## Commits

|   # | Commit                                      | Lines | What to check                                                                                                                                                                         |
| --: | ------------------------------------------- | ----: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|   1 | open a file on its cited lines              |   210 | Renders lines 337–365 for a 345–357 reference (8 lines of padding). Pierre's `renderRange` takes a zero-based start, and the test asserts the first visible line.                     |
|   2 | fold bars named after the hidden definition |   180 | `enclosingSymbol` scans upward for a `def`, `class`, or `function` line. Tests cover Python, JavaScript, and a file with no definitions, which falls back to the line count.          |
|   3 | keep the reader's line when a fold expands  |   120 | Expanding the upper fold inserts rows above the viewport. The pane saves the line under the cursor and its pixel offset before rendering and restores them after. Read with its test. |
|   4 | notes as gutter markers                     |   240 | Pierre renders into a shadow root, so marker styles are an adopted stylesheet on that root. A marker on a folded line is drawn on the fold bar.                                       |
|   5 | selected lines as a composer chip           |   150 | Reads the selection into `{path, ref, start, end}` and appends a chip. No helper changes.                                                                                             |

## Checked

- 12 tests added, one file per commit, run by `node --test tests/visual-review`: the first visible line for a 345–357 reference, the fold bar's name in Python, JavaScript, and a file with no definitions, the cursor line after a fold expands, a marker on a folded line, and the chip's `{path, ref, start, end}`.
- Opened `src/session.py:345-357` from a page, expanded both folds to the ends of the file, and opened a 20,000-line file at lines 10001–10010. Both files come from the `play.mjs` fixture in this pull request.

![The pane at lines 345–357 with both fold bars](pane.png)
![A marker's note open under its line](marker.png)
```

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
- Add a review comment of your own only as a last resort, for one hunk whose
  reason fits neither in the code nor in the commit message.
