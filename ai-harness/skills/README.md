# Skills

`worktrees` is the one skill kept here, because it teaches agents `ws`, which
this repo builds. Claude Code and Codex read it through links into this
folder, so an edit here applies at their next session.

| Skill                              | Description                                                 |
| ---------------------------------- | ----------------------------------------------------------- |
| [`worktrees`](worktrees/SKILL.md)  | Start, watch, message and remove worktree agents with `ws`. |

Every other skill comes from the tool that owns it. Each home switch runs
pair's `npx skills add RyanSaxe/pair -g` when its skill is missing, and
byor and Rex install their own.
[`link-agent-skills.sh`](../tools/link-agent-skills.sh) links a skill that
lands only in `~/.agents/skills` into `~/.claude/skills`, so that Claude
finds it too.
