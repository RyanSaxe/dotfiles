# Global agent instructions

Optimize the work for the person driving it. Make the code, decisions, commits,
and explanations easy for them to understand and review.

## Work with the driver

- Understand the requested outcome and the existing system before changing it.
- Ask when an unresolved choice would materially change the result. Otherwise,
  make the smallest safe assumption, state it, and continue.
- Challenge plans that create unnecessary complexity or conflict with the
  evidence. Once the driver decides, implement that decision faithfully.
- Lead with outcomes, decisions, and blockers. Use concise, concrete language;
  avoid jargon, vague abstractions, and narration of routine work.
- Never claim more than the evidence demonstrates.

## Isolate feature work

Use Workmux for feature development that can be isolated in a worktree. Create
or resume the worktree before editing. Do not create a nested worktree when the
task is already in one. Read-only investigation and genuinely trivial changes
do not require a new worktree.

## Make focused changes

- Solve the current problem with the smallest coherent design. Do not build for
  speculative futures.
- Follow the repository's established structure and toolchain. Align with the
  driver before adding a dependency, abstraction, or public interface.
- Treat existing changes as intentional. Do not revert work you did not create.
- Do not change environment files, dependency lock files, or generated state
  unless the driver explicitly asks or the requested change requires it.
- Keep experiments, logs, screenshots, and disposable scripts outside the
  repository, preferably in `/tmp`.
- Write code that explains itself through names, types, and structure. Comments
  should explain decisions or constraints that the code cannot make obvious.

## Build reviewable history

Treat the commit sequence as a primary interface for human review. A reviewer
should be able to understand the change by reading the commits in order.

- Commit completed implementation work in coherent, independently reviewable
  units. Avoid both unrelated bundles and meaningless micro-commits.
- Preserve the reasoning that led to the final design, not experiments and
  abandoned approaches.
- Stage explicit paths or hunks and inspect the staged diff before committing.
  Never include scratch work, secrets, generated noise, or unrelated changes.
- Run the repository's pre-commit hooks. Fix failures caused by the change;
  bypass or suppress a diagnostic only when the exception is necessary and
  explained.
- Leave all intended work committed at handoff unless the driver asks otherwise.

Write pull request descriptions for the reviewer. Explain the outcome and why
it matters, give a useful review order when needed, report verification, and
call out risks or unresolved decisions. Do not turn the description into an
activity log.

## Read the relevant guide

- Before writing or materially changing tests, read
  [Testing](references/testing.md).
- Before finalizing an implementation, read
  [Verification](references/verification.md).
- Before writing or substantially revising documentation or another durable
  review artifact, read [Writing](references/writing.md).
