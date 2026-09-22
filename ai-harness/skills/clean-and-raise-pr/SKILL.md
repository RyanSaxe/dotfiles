---
name: clean-and-raise-pr
description: Turn unpolished work into a pull request a reviewer can trust. Verifies the change through its real interface, audits and adds tests, simplifies the code, updates the documentation, rebuilds the commit history into a reviewable series, writes the description for the reviewer, opens a draft, watches CI to green, and marks the pull request ready. Use when invoked by name, when the user says finished work should be cleaned up, made reviewable or polished into a pull request, or when they point at code that needs verifying and tidying before anyone reviews it. Do not use for a plain request to open or create a pull request, and do not use it to build a feature.
---

# Clean and raise a pull request

Take a branch whose implementation is finished and turn it into a pull
request that is ready to review. Run every phase every time, sized to the
change: a one-line fix gets a three-line brief and one commit, a large
feature gets a user simulation and a rebuilt commit series. Skip the
history rebuild only when the branch is already one clean commit.

Requirements: `git`, and `gh` authenticated for the repository (`gh auth
status`). Attaching images to the pull request needs gh 2.99.0 or newer. If
a requirement is missing, tell the user what to install or upgrade and stop.

## Writing

[writing.md](references/writing.md) covers every sentence this skill
writes: the brief, the commit messages, the pull request body and the final
report. Read it before the brief. Two rules sit here instead, because they
are about this skill and not about sentences.

- Do not describe the diff line by line, do not describe what you did during
  the session, and do not repeat the ask.
- Do not write "not done", "not checked", or "I did not" lines. Do the work
  or leave the sentence out.

## Phases

1. Align: read the ask and the diff, post a brief, wait for a go.
2. Verify: run the project's checks, audit the tests, use the change, run a
   user simulation.
3. Simplify: remove what the change no longer needs; run the checks again.
4. Document: add the documentation the change needs; fix any it made wrong.
5. Rebuild history: one concept per commit, within the size range, each
   passing the checks.
6. Describe: write the pull request body.
7. Open: open a draft, watch CI, fix failures, mark it ready.

After the go, run every phase and report once at the end. Stop early only if
CI still fails after three fix attempts, verification finds a bug that
changes the scope, or the history rebuild fails its identity check twice.
When you stop early, say what happened and what is left.

## Align

The base branch is the one the user named. If none, use the open pull
request's base. If there is no pull request, use the default branch from
`gh repo view --json defaultBranchRef`. Read every file under `references/`
first: the brief uses their definitions of checks, the simulation, docs, and
commits. Read the original ask if it exists in the conversation or in a file
the user points to. If there is no record of the ask, the branch is the
ask: compare Outcome against what its commits and pull request say, and
say so in the brief. Then read the whole diff and the branch's commits:

    git fetch origin
    git diff origin/<base>...HEAD
    git log --reverse --shortstat origin/<base>..HEAD

Post a brief and wait for the user's go. Always include Outcome and Size.
Include the other lines only when they apply.

- Outcome: what the branch does compared with the ask, in one sentence, and
  any gap.
- Size: the estimated number of hand-written lines and of commits, using the
  size range in [history.md](references/history.md). Above about 2,000
  lines, propose one core pull request and separate pull requests on top of
  it, list them in a table, and say that the user can answer "one PR" to
  keep it whole. Name the commits by subject when their grouping is not
  obvious. Say which paths are fixtures, generated files, or vendored code;
  the rebuild leaves them out of the count.
- Separate: any unrelated change that should be its own pull request from
  the base: what it is, how many lines, and that it goes first.
- Verify: the project's checks, how you will use the change yourself, and
  the user simulation if there is behavior you cannot check by using it:
  who the user is and what they try.
- Docs: which documents you will add or update beyond what the branch
  already has, or that none are needed.
- Decide: each decision that changes the result, with a recommendation.

Most branches are one pull request. Propose a split only above 2,000 lines,
and a separate pull request only for unrelated work. Do neither before the
go. When the Size line proposes a split, end the brief with one line saying
the sizes are estimates and the rebuild will report measured ones.

A brief for a small change:

    Outcome: the sidebar dims windows idle for ten minutes; matches the ask, no gap.
    Size: about 60 lines, two commits.
    Separate: the .editorconfig change is unrelated; it goes first, alone.
    Verify: make check; open the sidebar with two windows and idle one; a user who reads only the README tries to change the threshold.
    Docs: threshold section in the README; nothing else mentions idling.
    Decide: default threshold ten minutes (recommended) or five.

A brief that proposes a split adds the table and the estimate line:

    Size: 8,800 hand-written lines, about 41 commits at review grain. Above 2,000 lines, so I propose one core pull request and eight on top of it. Say "one PR" to keep it whole.

      pull request            commits   lines
      core                          8   1,500   skill folder, helper server, app shell
      repository routes             6     900
      agent loop and thread         6   1,000
      page grammar                  5   1,060
      blocks                        6   1,100
      code pane                     5     900
      quick open                    3     400
      export                        4     800
      fixtures                      2     240

    Sizes are estimates; the rebuild reports the measured ones.

The user's go may cut a phase ("one PR", "one commit", "skip the user
simulation"). Do what it says and skip nothing else.

After the go, first move any change that gets its own pull request: create a
branch from the base in a separate worktree
(`git worktree add ../<name> -b <name> origin/<base>`), cherry-pick or copy
the change there, remove it from this branch, and commit on both. Run the
remaining phases on that branch as well, sized to it, without a second
brief.

## Verify

Read [verification.md](references/verification.md). Run the project's own
checks: formatting, linting, types, tests. Audit the tests that cover the
change, adding and deleting as verification.md says. Use the change the way
a user would. Run the user simulation when using the change yourself leaves
some behavior unchecked. A change you can check completely by using it needs
none.

Fix what verification finds: a bug, a missing test, a bad test, or a wrong
document goes in this pull request, in its own commit when it is a separate
concept. Do not fix a finding unrelated to the change. Report it to the user
at the end, open an issue if the repository uses them, and keep it out of
the body. If a fix would change the scope of the ask, stop and report.

## Simplify

Read [simplification.md](references/simplification.md) and apply it to the
diff. After each pass that changes something, run the checks again. Stop
when a pass changes nothing.

## Document

Read [documentation.md](references/documentation.md). Add the documentation
the change needs, fix every document the change made wrong, and run every
example you touched. Run the checks again if anything changed.

## Rebuild history

Skip this phase when the diff is one concept and already one clean commit.
Otherwise read [history.md](references/history.md): read the branch's
commits, repair them if each is already one concept, rebuild them from the
final tree if not, and measure every commit. Never rewrite history on a pull
request that has review comments. That is why the pull request is opened
last.

## Describe

Read [description.md](references/description.md). Write the body to a file
outside the working tree and keep the file for the next phase. Use the
measured sizes from the rebuild in the commit table.

## Open

One pull request: rebase onto the current base, push, and open as a draft:

    git fetch origin && git rebase origin/<base>
    git push --force-with-lease -u origin HEAD
    gh pr create --draft --base <base> --title "<title>" --body-file <file> [--attach '<image>#<alt>']

For an existing pull request that is a draft with no review comments:
rebase onto the base, push the rebuilt series with
`git push --force-with-lease`, and update the body with
`gh pr edit --body-file <file> [--attach '<image>#<alt>']`. If it has
review comments, add commits on top, push without force, and update the
body the same way. Pass every image the body references with `--attach`,
on create and on edit alike; a local path alone renders as a broken image.

Several pull requests, in this order:

1. Open each separate pull request from the base first. Watch its CI and
   mark it ready before the next step.
2. Rebase the core onto the base, push it, and open it as a draft against
   the base.
3. Push each group branch and open it as a draft with
   `--base <core branch>`, in the order the brief listed.
4. Watch CI on every pull request and mark them ready in the same order.
   After the core merges, check each group pull request's base with
   `gh pr view --json baseRefName`; if GitHub did not move it to the base,
   run `gh pr edit --base <base>`.

GitHub runs no CI on a pull request that conflicts with its base, so check
that it is mergeable first. `UNKNOWN` means GitHub is still computing; ask
again a few times over the next minute. `CONFLICTING` means rebase and push
again:

    gh pr view --json mergeable -q .mergeable

Watch CI:

    gh pr checks --watch --fail-fast

If it reports no checks, wait and retry; a check can take a moment to
appear. When a check fails, read its log, fix the cause, push, and watch
again, at most three times:

    gh run list --branch <branch> --limit 3
    gh run view <run-id> --log-failed

If the repository has no checks, say so in the final report. When every
check passes, mark the pull request ready:

    gh pr ready

Report back with the pull request links, what was checked (the same facts
as the body's Checked part), and anything outside the pull request the user
needs to decide.
