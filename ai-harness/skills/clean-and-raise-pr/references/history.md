# Commit history

The reviewer reads the commits in order. Each commit is small enough to read
in one sitting, and the sequence explains the change without the pull
request body.

## The unit

- A commit is one concept: one capability, one fix, or one refactor,
  whatever its size.
- Choose how fine the concepts are so that the series has the smallest
  number of small commits. Ten components can be ten commits, one commit,
  or three, depending on which grouping is easiest to review.
- Most commits are 50 to 500 lines. 200 is a good size. Above 200 is harder
  to review but acceptable. Go to 500 when the concept needs it. Above
  1,000, reviewers refuse. Between 500 and 1,000, split when a smaller
  grouping is as easy to review; keep the commit whole when the pieces only
  make sense together. A 2,000-line commit is rare; when one is
  necessary, its message says why.
- Count lines as insertions plus deletions, excluding paths the brief listed
  as fixtures, generated files, or vendored code. Put those paths in their
  own commit and say what they are in the subject.
- Every commit builds, passes the project's checks, and includes its own
  tests and documentation. No fixup commits.
- Order the commits as preparation, then the change, then cleanup.

## Repair or rebuild

Read the branch's commits before changing anything:

    base=$(git merge-base origin/<base> HEAD)
    git log --reverse --shortstat --format='%h %s' "$base"..HEAD

**Repair** when each commit is already one concept and only small fixes are
needed: squash a fixup into the commit it fixes, reorder, reword a subject
or body, split a commit that is over 1,000 lines. Leave every other commit
unchanged.

**Rebuild** when the branch is one large commit, when its commits are not
concepts, or when a later commit rewrites most of what earlier commits added
and the reviewer should read each file once. Reset to the base and commit
the final tree again, one concept at a time. When one file belongs to
several commits, write the version of the file for the current commit,
stage it, commit, then restore the final version for the next commit with
`git checkout <branch>-before-rewrite -- <files>`.

Never rewrite history on a pull request that has review comments; the
comments lose their place in the code. Rewrite before the pull request
exists, or while it is a draft with no comments.

## Procedure

Both approaches keep a backup, check that every commit passes on its own,
check that the final tree is unchanged, and measure every commit.

1. Commit all work first; the messages get replaced. Changes for other pull
   requests must already be off this branch. Record the starting point:

       base=$(git merge-base origin/<base> HEAD)
       before=$(git rev-parse 'HEAD^{tree}')
       git branch <branch>-before-rewrite

2. To repair, run a rebase with a todo file you write yourself, because
   there is no interactive editor:

       GIT_SEQUENCE_EDITOR='cp <todo file>' git rebase -i "$base"

   Replace a message with `exec git commit --amend -F <message file>` under
   the commit it belongs to, and split a commit by stopping at it with
   `edit`, then `git reset HEAD^` and commit the pieces.

   To rebuild:

       git reset --soft "$base" && git reset

   then stage and commit each concept in order. If the brief proposed a
   split, commit the core first and then each group, so each group is a
   contiguous range of commits.

3. Check that every commit passes on its own:

       git -c sequence.editor=: rebase -x '<checks>' "$base"

   Run the checks in a mode that does not modify files; a formatter that
   rewrites files leaves a dirty tree and stops the rebase. If the checks can modify
   files, append `&& git diff --quiet` so a modified file fails the step. A
   failing commit means the split is wrong, usually because it needs
   something a later commit adds, or because a validator needs a file the
   directory does not have yet. Abort, reset to the backup, and move that
   piece to the earlier commit.

4. Check that the final tree is unchanged:

       [ "$(git rev-parse 'HEAD^{tree}')" = "$before" ] && echo identical

5. Measure every commit:

       git log --reverse --format='%h %s' "$base"..HEAD | while read -r h s; do
         printf '%s %6s  %s\n' "$h" \
           "$(git show --shortstat --format= "$h" -- . ':!<fixture paths>' \
              | awk '{a+=$4; d+=$6} END {print a+d}')" "$s"
       done

   Drop the `':!<fixture paths>'` argument when the brief listed no such
   paths. A commit over 1,000 lines whose message does not say why fails
   this step: split it or write the reason. Use this output for the commit table
   in the description; these are the measured sizes, the brief's were
   estimates.

If step 3 or 4 fails, run `git reset --hard <branch>-before-rewrite` and try
once more. If it fails again, stop and report what differed. Keep
`<branch>-before-rewrite` until the pull request is open and its checks
pass, then delete it.

## Messages

Read `git log --oneline -30` and use the repository's subject style: a
prefix like `fix(scope):`, a bare imperative, or a ticket number. Say what
the change does, short enough for a one-line log.

Add a body only when the subject cannot explain why. Write three to six
lines: the problem, why this solution rather than the obvious one, and what
the commit leaves out. Do not repeat what the diff shows. Do not describe
the code.

    feat(visual-review): keep the reader's line when a fold expands

    Expanding the upper fold inserts 60 rows above the viewport and the
    browser keeps scrollTop, so the visible text jumps. Save the line under
    the cursor and its offset before rendering, then restore them after.

A subject alone when the change explains itself:

    fix(rail): a visit only acks while someone is at the machine

A body that puts the reviewer where you were before the fix:

    interactive-plan: put the comment control in a gutter

    The control sat inside the block at its top right corner at 45%
    opacity, over a file header's Copy button and a table's last column,
    and it appeared only on hover. Ten of the twelve blocks on the Figures
    page clip their overflow to hold a rounded corner, which hid it, and
    the frame cannot change the overflow of a block a plan styles. It moves
    into the 40px gutter the reading column already reserves.

Trailers such as `Co-Authored-By` come from the harness or repository
configuration, not from this skill.

## Splitting

When the brief proposed a split and the user agreed, divide the series into
a core and groups. The core is this branch up to its last core commit. Each
group is a branch from the core's tip holding only that group's commits:

    git branch <core> <last core commit>
    git checkout -b <group> <core>
    git cherry-pick <group's first commit>^..<group's last commit>

When two groups add lines to the same list in a shared file, such as a
README options list or a test list, the later cherry-pick conflicts. Resolve
it by taking the core's version of the file and adding this group's lines.
Say in the final report that the groups must merge in order.
