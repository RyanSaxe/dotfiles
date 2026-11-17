# AGENTS.md

These are the user's standing instructions, and they apply to every task.
Follow them all, together with any other instructions you're given, such
as a skill's. An order matters only when two instructions say opposite
things. Then what the user asks for always comes first, next the AGENTS.md
closest to the file you're changing, then instructions you loaded for the
task at hand, and this file last.

Before you write anything a person will read, including your replies to
the user, read `~/generic/dotfiles/ai-harness/references/writing.md`.

## Before you start

- Read the instructions and code that govern the work, enough to choose a
  sound approach.
- Check each fact your work depends on at its source before you rely on
  it.
- Ask about any choice that could change correctness, scope, behavior or
  risk.
- During a long task, don't stop to ask. Decide, note what you assumed, and
  keep going. Stop only when going on could do harm that's hard to undo, or
  when the work can't continue.
- When the work adds or changes an interface that people or other
  components use, agree on it with the user before building it. The tests
  and docs then describe that interface.

## Writing code

Before you write code, read
`~/generic/dotfiles/ai-harness/references/development.md`. The references'
examples are in Python, and the same ideas apply in any language. These
rules apply to every change:

- Keep a change to what the task needs. Leave unrelated code, formatting and
  structure as they are, and don't add abstractions, options or error
  handling for cases that can't happen.
- Match the style of the code around it. Make the code explain itself, and
  write a comment only to say why.
- Fail clearly when an input, dependency or setting is missing. Don't add a
  fallback that hides a broken setup.
- Avoid implicit state machines, where it's unclear what can change what.
  When something has states, one component owns them and their valid
  transitions, consistent with the domain model.

## Testing and checking

Before writing or changing tests, read
`~/generic/dotfiles/ai-harness/references/testing.md`. Before checking that
work is done, read `~/generic/dotfiles/ai-harness/references/verification.md`.

- Test behavior that matters, through the interface people use. Delete a
  test you wrote only to drive a tricky piece of code before the work is
  done.
- Run the project's own checks, the ones its commit hook and CI run, and fix
  what your change breaks. Never silence a check to make it pass.
- Then use the change the way a person would, in the real program. Passing
  tests don't show that a feature works.

Debug on the smallest run that still shows the problem. When something
takes minutes or more to run, like a data pipeline or an end-to-end test,
give it a small mode that runs the same code on a sample of the input,
chosen by a flag or a config. Use it to reproduce a failure and try a fix in
seconds, and keep it working as the code changes.

Keep browser screenshots and traces outside project checkouts. With Playwright
MCP, omit the filename to use its configured output directory, or pass an
absolute path under that directory. Relative filenames resolve inside the
project checkout.

## From task to pull request

```text
task ─▶ build ─▶ clean up ─▶ pull request ─▶ checks pass ─▶ hand back
          ▲          │              │
          └── fix ◀──┴──────────────┘
```

Build the change in small slices, and check each one through the interface
people use. Then try the finished work as its users would, fix what that
finds, and shape it into commits a reviewer can follow.
Raise the pull request, as a draft or ready, and follow its checks until they
pass, going back to fix whatever fails.

Work in a separate worktree when the change runs alongside other work in the
same repository, or when the user asks for one, and make it with `ws`, as the
worktrees skill describes. Otherwise work in the checkout you're in.

## Commits, pull requests and docs

People who weren't part of the work read these, often in public. Describe
the change from what's in the repository, and leave out anything a reader
can't find there, this conversation included. Mention something from outside
the repository only when the repository already does or the user asks.

Make each commit one coherent step of the change. Keep every doc, example
and comment that your change affects accurate, and never leave stale
guidance behind.

Plans, notes and scratch files go in `agent-notes/` at the repository root.
The global git ignore keeps that folder out of every repository.

## Other agents

To start an agent in another terminal and work with it, run
`pair spawn CLI --prompt "…"`, which prints the name to message it by. Read
`pair spawn --help` before you start one, for the CLIs it can start and how
to pass a CLI its own flags. `pair message --to NAME --text "…"` sends it a
message, and `pair agents` lists the sessions that are running.

## This computer

`~/generic/dotfiles` sets up this computer with Nix, these instructions
included. Read its AGENTS.md before you install a tool or change a setting.
A general-purpose tool goes in through Nix there, not a global `brew`, `pip`
or `npm` install, so every computer gets the same one. The dotfiles are
public, so private and internal tools never go in them. Install a tool that
only one project needs in that project's own environment. Ask when you can't
tell.

## The wiki

`$VAULT_DIR/wiki` is what earlier sessions learned and wrote down for later
ones.

- Before you work in an area, read `$VAULT_DIR/wiki/index.md` for pages on
  it. When something surprises you, search the wiki first with
  `rg -i 'WORDS' "$VAULT_DIR/wiki"`. A page may already explain it.
- When you learn something worth knowing again, write it there, as the wiki
  skill describes.
- Your harness's own memory tool is for how to work with the user, and it
  stays with one agent on one computer. The wiki is for what's true about the
  world, and the user and every agent read it.
