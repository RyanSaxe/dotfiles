# Hunk Follow And Comment Agent

## Goal

Build a workflow where a human can keep a live Hunk review session open while a
CLI coding agent works, and the coding agent can delegate review annotations to a
dedicated Hunk comment subagent at coherent checkpoints.

The feature has two cooperating parts:

1. `hunk-follow`: a small local companion that opens and tracks a follow-marked
   Hunk session, keeps it current with the active work, and moves that session to
   the newest relevant changed hunk or comment.
2. `hunk_commenter`: a Codex custom subagent that uses the Hunk skill and
   `hunk session ...` commands to leave sparse, actionable inline comments in the
   live Hunk session.

This should not create a second review database, prompt API, or separate comment
store. Hunk remains the source of truth for the visible diff and comments.

## Non-Goals

- Do not build a `hunk-follow reviewer-prompt` command or any agent-prompt API.
- Do not make the daemon spawn AI agents.
- Do not call the comment subagent after every file write.
- Do not let the comment subagent edit source files.
- Do not move ordinary Hunk sessions that the human opened for manual review.
- Do not require IDE-specific hooks.

## Expected User Experience

Typical flow:

```bash
cd ~/work/project
hunk-follow
```

That command should:

1. Require a clean tree by default.
2. Resolve the current `HEAD` to a concrete commit SHA.
3. Open or reuse a dedicated tmux session named `hunk`.
4. Run a Hunk diff in watch mode, usually:

   ```bash
   hunk diff <base-sha>...HEAD --watch --exclude-untracked
   ```

5. Mark that Hunk pane as a follow session with tmux pane options.
6. Ensure the `hunk-follow` daemon is running.

As the AI commits or edits, the Hunk view refreshes through Hunk's own
`--watch` behavior. The follow daemon adds movement: it navigates the marked
Hunk session to the newest relevant changed hunk or newly added comment.

When the main coding agent reaches a review checkpoint, it checks for a live
Hunk session and spawns the `hunk_commenter` subagent. The subagent inspects the
live Hunk diff and leaves comments directly in Hunk.

## Repository Changes

Implement this in the dotfiles repo with these files:

- `scripts/hunk-follow.py`: reusable PEP 723 Python script.
- `zsh/aliases.zsh`: add `alias hunk-follow='uv run -q --script ~/generic/dotfiles/scripts/hunk-follow.py'`.
- `ai-harness/codex/agents/hunk-commenter.toml`: Codex custom subagent.
- `ai-harness/AGENTS.md`: routing instruction that tells Codex when to spawn
  `hunk_commenter`.
- `ai-harness/codex/rules/hunk.rules`: Codex approval rules for Hunk session
  commands, if project/user rules are wired through this repo.
- `config/symlinks.txt`: add the Codex agents directory symlink:

  ```text
  ai-harness/codex/agents:$HOME/.codex/agents
  ```

- `hunk/README.md`: add a short user-facing workflow section once implemented.

Optional parity files:

- `ai-harness/claude/agents/hunk-commenter.md`
- `ai-harness/copilot/agents/hunk-commenter.agent.md`
- matching symlinks to `~/.claude/agents` and `~/.copilot/agents`

## Hunk Follow CLI

Implement `scripts/hunk-follow.py` as a Python 3.11+ PEP 723 script. Use only
stdlib dependencies unless there is a strong reason to add one.

Required commands:

```text
hunk-follow [open] [--repo PATH] [--base REV] [--worktree] [--session NAME] [--path PATH ...] [--no-attach]
hunk-follow daemon [--foreground] [--interval SECONDS]
hunk-follow status [--json]
hunk-follow stop
hunk-follow mark --pane PANE_ID --repo PATH --base SHA --mode MODE
hunk-follow unmark --pane PANE_ID
```

`hunk-follow` with no subcommand should behave like `hunk-follow open`.

Do not add commands that generate agent prompts. The agent behavior belongs in
custom agent files and `AGENTS.md`.

### Open Command

Preflight:

1. Resolve the repo root with:

   ```bash
   git -C "$repo" rev-parse --show-toplevel
   ```

2. Verify `git`, `hunk`, and `tmux` are available.
3. If `--worktree` is not set, require `git status --porcelain` to be empty.
   This includes untracked files. If not clean, fail with:

   ```text
   hunk-follow requires a clean tree. Commit/stash changes or use --worktree.
   ```

4. Resolve the base once to a concrete commit SHA:

   ```bash
   git -C "$repo" rev-parse --verify "${base:-HEAD}^{commit}"
   ```

   Store the SHA, not the symbolic ref. This matters because `HEAD` moves when
   the AI commits.

Diff command construction:

- Default committed-follow mode:

  ```bash
  hunk diff "$base_sha...HEAD" --watch --exclude-untracked
  ```

- Worktree mode without `--base`:

  ```bash
  hunk diff --watch --exclude-untracked
  ```

- Worktree mode with `--base`:

  ```bash
  hunk diff "$base_sha" --watch --exclude-untracked
  ```

- If `--path` is passed, append `-- <path...>` after the diff target.

Tmux behavior:

1. Create or reuse a dedicated tmux session, default name `hunk`.
2. Use one window per repo. A stable window name should be derived from the repo
   directory name and deduplicated if needed.
3. Start Hunk in that window:

   ```bash
   cd "$repo" && hunk diff ...
   ```

4. Mark the pane with tmux pane options:

   ```bash
   tmux set-option -pt "$pane" @hunk-follow 1
   tmux set-option -pt "$pane" @hunk-follow-repo "$repo"
   tmux set-option -pt "$pane" @hunk-follow-base "$base_sha"
   tmux set-option -pt "$pane" @hunk-follow-mode "committed"
   tmux set-option -pt "$pane" @hunk-follow-paths "$json_paths"
   ```

5. Start the daemon if it is not already running.
6. If stdout is a TTY and `--no-attach` is not passed, attach or switch to the
   tmux session. If not interactive, print the attach command:

   ```bash
   tmux attach -t hunk
   ```

### Daemon Command

The daemon should be harness agnostic. It watches Hunk/tmux/git state, not AI
tool events.

Use an in-memory state map keyed by Hunk session id. A small PID file is fine for
singleton management, but do not persist review state or comments outside Hunk.

Loop every `--interval`, default `0.75` seconds:

1. Discover live Hunk sessions:

   ```bash
   hunk session list --json
   ```

2. For each session, find the tmux pane id exposed in the session metadata.
3. Keep only sessions whose pane has `@hunk-follow=1`.
4. Read pane options for repo, base SHA, mode, and path filters.
5. For each follow session, detect events and navigate if useful.

Event priority:

1. New Hunk comments.
2. New commit or changed `HEAD`.
3. Worktree file changes.

Comments should win because they are direct review attention requests.

### Comment Event Handling

Track seen comment ids per Hunk session in daemon memory.

On each loop:

1. Read session details with JSON output, preferring:

   ```bash
   hunk session get "$session_id" --json
   hunk session review "$session_id" --json
   ```

2. If comment ids are exposed there, use them directly. If current Hunk does not
   expose comment ids in JSON, add `--json` support to:

   ```bash
   hunk session comment list
   ```

   before implementing comment-follow. Avoid parsing human-oriented text output
   for this feature.

3. For the newest unseen comment, navigate to its exact location:

   ```bash
   hunk session navigate "$session_id" --file "$file" --new-line "$line"
   ```

   Use `--old-line` when the comment targets the old side. If exact side/line is
   unavailable, fall back to:

   ```bash
   hunk session navigate "$session_id" --next-comment
   ```

4. Mark all currently visible comments as seen after handling the newest one, so
   batches do not cause repeated jumps.

If the comment was added through `hunk session comment apply --focus`, Hunk may
already jump. The daemon should still record the comment as seen so it does not
fight the current focus on the next loop.

### Code Change Event Handling

The daemon is not a file-write hook, so it cannot know the exact latest edited
line in all cases. Use a practical approximation:

1. Detect `HEAD` changes with:

   ```bash
   git -C "$repo" rev-parse HEAD
   ```

2. Detect worktree changes with a cheap poll:

   ```bash
   git -C "$repo" status --porcelain=v1 -uno
   ```

3. Build candidate changed files:

   - committed mode:

     ```bash
     git -C "$repo" diff --name-only "$base_sha...HEAD"
     ```

   - worktree mode:

     ```bash
     git -C "$repo" diff --name-only
     ```

4. Sort candidate files by filesystem mtime descending when files exist on disk.
5. Intersect candidates with files present in `hunk session review --json`.
6. For the best candidate file, compute a target hunk:

   - Parse `git diff --unified=0` for that file.
   - Prefer the last changed new-side range.
   - If parsing fails, navigate to the last hunk in that file.

7. Navigate:

   ```bash
   hunk session navigate "$session_id" --file "$file" --new-line "$line"
   ```

Debounce navigation per session for at least 500 ms after a detected change. If
multiple changes happen during the debounce window, jump once to the newest
candidate.

### Multiple Hunk Sessions

Multiple sessions are expected.

Rules:

- Only sessions marked with `@hunk-follow=1` move automatically.
- A normal `hunk diff --watch` session stays human-controlled.
- If two follow sessions show the same repo and both contain the changed file,
  both may jump.
- If a follow session was opened with path filters, it should only jump for
  files present in that session's current review JSON.
- If no visible diff file matches the changed file, do nothing for that session.

This lets a user keep two sessions open:

- one follow session that tracks the AI,
- one manual session that never moves unless the human or agent explicitly
  navigates it.

### Human Override

Implement a simple lock before adding popups:

```bash
tmux set-option -pt "$pane" @hunk-follow-lock 1
tmux set-option -pt "$pane" @hunk-follow-lock 0
```

When locked, the daemon should keep observing comments and changes but skip
navigation.

A tmux popup veto can be added later, but it should not be in v1. It adds UI
complexity and can fight the main benefit of a dedicated follow session.

### Status Command

`hunk-follow status --json` should report:

```json
{
  "daemon": {"running": true, "pid": 12345},
  "sessions": [
    {
      "hunkSessionId": "...",
      "repo": "/path/to/repo",
      "pane": "%44",
      "mode": "committed",
      "base": "abc123...",
      "locked": false,
      "visibleFiles": 12,
      "lastJump": {
        "kind": "comment",
        "file": "src/app.ts",
        "line": 42,
        "at": "2026-05-08T15:00:00Z"
      }
    }
  ]
}
```

This is for diagnostics only. It is not an agent prompt API.

## Codex Custom Subagent

Codex supports custom subagents as TOML files under `~/.codex/agents/` or
project-local `.codex/agents/`. The official docs describe `name`,
`description`, and `developer_instructions` as required fields:

- <https://developers.openai.com/codex/subagents>
- <https://developers.openai.com/codex/concepts/subagents>

Create:

```toml
# ai-harness/codex/agents/hunk-commenter.toml
name = "hunk_commenter"
description = """
Use this agent when a live Hunk session is open for the current repo and the
main agent reaches a review checkpoint: before committing, before final handoff,
after a substantial coherent change, after risky edits, or when the user asks
for Hunk comments. This agent leaves Hunk comments only. It must not edit source
files.
"""

model_reasoning_effort = "high"
sandbox_mode = "workspace-write"

developer_instructions = """
You are a focused Hunk review-comment agent.

Your job is to inspect the live Hunk session for the current repository and
leave sparse, actionable inline comments.

Rules:
- Use `hunk skill path` and follow the Hunk skill instructions.
- Use non-interactive `hunk session ...` commands only. Do not run interactive
  `hunk diff` or `hunk show`.
- Select the live Hunk session whose repo root matches the current repository.
- If multiple sessions match, prefer a session whose tmux pane has
  `@hunk-follow=1`. Otherwise report the ambiguity and stop.
- Leave comments only for correctness risks, missing migration steps, broken
  assumptions, risky edge cases, or review-blocking ambiguity.
- Do not edit source files.
- Do not run broad tests unless explicitly asked.
- Do not summarize the whole diff unless asked.
- Prefer 0-5 high-signal comments.
- If no matching live Hunk session exists, report that and stop.

Suggested workflow:
1. Run `hunk skill path`.
2. Read the skill instructions.
3. Run `hunk session list --json`.
4. Inspect the matching session with `hunk session review --json`; add
   `--include-patch` only for files/hunks that need raw diff text.
5. Add comments with `hunk session comment add` or batch them with
   `hunk session comment apply --stdin --focus`.
6. Return a short summary of comments added, or say no comments were warranted.
"""
```

### Codex Routing Instruction

Add this to `ai-harness/AGENTS.md`:

```markdown
## Hunk Comment Checkpoints

When working on code and a meaningful review checkpoint is reached, check
whether a live Hunk session exists for this repo with `hunk session list --json`.
If one exists, spawn the `hunk_commenter` subagent to leave Hunk comments.

Review checkpoints include:

- before committing,
- before final handoff,
- after substantial or risky edits,
- after a test failure/fix cycle that changed the implementation,
- when the user explicitly asks for Hunk comments.

Do not spawn `hunk_commenter` after every file write. Do not ask it to edit
source files. The subagent's output should be a short summary; the review
comments themselves belong in Hunk.
```

This routing instruction is the explicit authorization Codex needs to use the
subagent at checkpoints. Codex docs state that subagents are not spawned
automatically unless explicitly requested or instructed.

### Codex Rules

Earlier local testing showed `hunk session list --json` can return no sessions
inside the sandbox while working outside the sandbox. Add explicit rules so
Codex can inspect and annotate live Hunk sessions.

Create:

```text
# ai-harness/codex/rules/hunk.rules
prefix_rule(
    pattern = ["hunk", "skill", "path"],
    decision = "allow",
    justification = "Allow agents to locate the Hunk review skill.",
)

prefix_rule(
    pattern = ["hunk", "session", ["list", "get", "context", "review", "navigate", "reload"]],
    decision = "allow",
    justification = "Allow agents to inspect and navigate live Hunk sessions.",
)

prefix_rule(
    pattern = ["hunk", "session", "comment", ["add", "apply", "list"]],
    decision = "allow",
    justification = "Allow the Hunk comment agent to add and inspect inline review comments.",
)

prefix_rule(
    pattern = ["hunk", "session", "comment", ["rm", "clear"]],
    decision = "prompt",
    justification = "Removing Hunk comments should require explicit approval.",
)
```

Wire this through `config/symlinks.txt` if rules are managed from this repo:

```text
ai-harness/codex/rules:$HOME/.codex/rules
```

If that conflicts with existing user-level rules, merge carefully instead of
overwriting.

## Claude And Copilot Parity

These are optional after Codex works.

Claude Code supports project agents at `.claude/agents/` and user agents at
`~/.claude/agents/`:

- <https://docs.claude.com/en/docs/claude-code/subagents>

GitHub Copilot CLI supports project agents at `.github/agents/` and user agents
at `~/.copilot/agents/`:

- <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli>

The same `hunk-commenter` prompt should be ported to those formats after the
Codex version has been validated. Keep the behavior identical:

- inspect Hunk,
- leave comments,
- do not edit source,
- stop if no matching session exists.

## Acceptance Tests

### CLI Unit Tests

Add tests for pure functions in `scripts/hunk-follow.py`:

- clean-tree detection rejects dirty and untracked files in default mode,
- base ref resolution stores a concrete SHA,
- Hunk diff command rendering for committed mode, worktree mode, and path
  filters,
- tmux option parsing,
- follow-session filtering,
- review JSON file matching,
- diff hunk line extraction from `git diff --unified=0`,
- event priority: new comment beats file change.

### Local Integration Tests

Use temporary git repositories and tmux sessions.

Scenarios:

1. Clean default start:
   - create repo,
   - commit baseline,
   - run `hunk-follow --no-attach`,
   - verify one tmux pane is marked with `@hunk-follow=1`.

2. Dirty default rejection:
   - modify a tracked file,
   - run `hunk-follow`,
   - verify it exits non-zero with the clean-tree message.

3. Base SHA is frozen:
   - run `hunk-follow`,
   - make a commit,
   - verify pane option `@hunk-follow-base` is still the original SHA.

4. Multiple sessions:
   - open one follow Hunk session and one normal Hunk session,
   - change a file,
   - verify only the follow-marked session navigates.

5. Path-filtered sessions:
   - open two follow sessions with different paths,
   - change a file in one path,
   - verify only the relevant session navigates.

6. Comment jump:
   - add a Hunk comment through `hunk session comment apply --stdin`,
   - verify daemon navigates to that comment and records it as seen.

7. Subagent smoke test:
   - start a Codex session in a repo with a live Hunk session,
   - ask it to make a small risky change and use `hunk_commenter`,
   - verify Hunk receives comments and no source files are edited by the
     subagent.

### Manual QA

Manual flow to validate the actual experience:

1. Open a repo in one terminal.
2. Run `hunk-follow`.
3. Start Codex in another terminal.
4. Ask Codex to make a multi-file change.
5. Confirm the Hunk follow session stays refreshed and jumps to recent relevant
   hunks.
6. Before commit, confirm Codex spawns `hunk_commenter`.
7. Confirm comments appear in Hunk and the Hunk view jumps to the newest comment.
8. Open a second normal `hunk diff --watch` session and confirm it does not move.

## Rollout Plan

1. Build `hunk-follow open`, tmux marking, and `status`.
2. Add singleton daemon with follow-session discovery but no navigation.
3. Implement comment-follow navigation.
4. Implement code-change navigation.
5. Add Codex `hunk_commenter` and routing instructions.
6. Add Codex rules for Hunk session access.
7. Run integration tests and manual QA.
8. Add Claude/Copilot agent parity only after the Codex path is stable.

## Implementation Notes

- Prefer `hunk session review --json` before `--include-patch` to avoid filling
  agent context with full diffs.
- Use `hunk session comment apply --stdin --focus` when the subagent has several
  comments ready.
- Keep comment batches small. A good default is 0-5 comments.
- Treat Hunk comments as review annotations, not a task tracker.
- Keep `hunk-follow` and `hunk_commenter` loosely coupled. The only coupling
  should be that follow sessions are discoverable through Hunk session metadata
  and tmux pane options.
- If Hunk lacks a needed JSON field, add JSON support to Hunk rather than
  parsing terminal-oriented text.
