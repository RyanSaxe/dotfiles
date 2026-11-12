---
name: worktrees
description: Start, watch, message and remove worktree agents with `ws`. Use when work should run in its own git worktree, when starting other agents in parallel, or when checking on or cleaning up worktrees.
---

# Worktrees

`ws` puts a piece of work in its own git worktree at
`~/worktrees/PROJECT/NAME`, with its own Rex or tmux session and an agent
started on a prompt. It works out whether it runs in Rex, in tmux or in
neither by itself.

## When to use one

- Isolate feature work in a worktree: create or resume it before editing.
- Skip it for read-only investigation and trivial changes, and never create
  a worktree inside a worktree.
- Split work across worktrees only when the pieces can be built and reviewed
  separately.

## Start one

```sh
ws new NAME --agent claude --prompt "…"
```

- Start the same agent you are. Claude Code starts `claude` and Codex starts
  `codex`, unless the user names another.
- NAME becomes the branch and the folder. Use a short kebab-case name for the
  change.
- The prompt is the agent's whole brief: the goal, the files to read, what is
  out of scope, and how to verify. The agent knows nothing else.
- `--base REF` branches from REF instead of the current HEAD. Fetch first and
  pass `origin/BRANCH`, so the base is current.
- Run by an agent, `ws new` opens the session without switching the user's
  view. Outside Rex and tmux it only creates the worktree and prints its
  path, so do the work there yourself.
- `ws pr NUMBER` does the same for a pull request.

## Watch and message

- `ws ls` lists worktrees by project with each session's agent state. Rex
  reports blocked, error, done, working or idle. tmux shows only open.
- In Rex, the rex skill covers reading an agent's screen.
- `ws send NAME "text"` types the text and Enter into that worktree's agent
  pane. Answer another agent only when the user asked you to coordinate.

## Clean up

`ws rm NAME` closes the session, removes the worktree and deletes the branch
once it is merged, which after a squash merge means GitHub shows its pull
request as merged. It refuses uncommitted changes and keeps an unmerged
branch. Pass `--force` only when the user said to discard the work.
