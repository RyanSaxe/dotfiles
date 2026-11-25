# Skills

Claude Code and Codex read the skills in this folder through links, so an
edit here applies at their next session.

| Skill                                     | Description                                                                      |
| ----------------------------------------- | -------------------------------------------------------------------------------- |
| [`worktrees`](worktrees/SKILL.md)         | Start, watch and remove worktree agents with `ws`, and message them with `pair`. |
| [`wiki`](wiki/SKILL.md)                   | Decide what agents learn is worth a page, and write it.                          |
| [`project-setup`](project-setup/SKILL.md) | Set up a repository's tools, checks and docs, or bring one in line.              |
| [`repo-docs`](repo-docs/SKILL.md)         | Write, organize and diagram repository READMEs and `docs/` trees.                |

Most other skills come from a private catalog, which installs them into
`~/.agents/skills`. Each home switch runs pair's
`npx skills add RyanSaxe/pair -g` when its skill is missing, and byor and
Rex install their own.
[`link-agent-skills.sh`](../tools/link-agent-skills.sh) links a skill that
lands only in `~/.agents/skills` into `~/.claude/skills`, so that Claude
finds it too.
