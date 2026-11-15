# Skills

Claude Code and Codex read the skills in this folder through links, so an
edit here applies at their next session.

| Skill                             | Description                                                  |
| --------------------------------- | ------------------------------------------------------------ |
| [`worktrees`](worktrees/SKILL.md) | Start, watch, message and remove worktree agents with `ws`.  |
| [`wiki`](wiki/SKILL.md)           | Write and tidy the wiki, the pages agents keep in the vault. |

Most other skills come from a private catalog, which installs them into
`~/.agents/skills`. Each home switch runs pair's
`npx skills add RyanSaxe/pair -g` when its skill is missing, and byor and
Rex install their own.
[`link-agent-skills.sh`](../tools/link-agent-skills.sh) links a skill that
lands only in `~/.agents/skills` into `~/.claude/skills`, so that Claude
finds it too.
