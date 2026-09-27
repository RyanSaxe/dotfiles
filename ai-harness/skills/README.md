# Skills

These skills are local copies used by the shared Claude Code, Codex CLI, and
GitHub Copilot CLI configuration. Edit the files here when you want to change
their behavior.

| Skill                                                                     | Description                                                                       | Source                                                                                                                                                                                                  |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`unslop`](unslop/SKILL.md)                                               | Cut AI tells from writing and add human voice.                                    | [Cursor plugins](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md), [raw file](https://raw.githubusercontent.com/cursor/plugins/refs/heads/main/pstack/skills/unslop/SKILL.md) |
| [`interactive-plan`](interactive-plan/SKILL.md)                           | Explicitly invoked browser-based planning and HTML handoff.                       | Local                                                                                                                                                                                                   |
| [`pair`](https://github.com/RyanSaxe/pair/blob/main/skills/pair/SKILL.md) | Explicitly invoked browser sessions to plan, build or explain work with an agent. | [RyanSaxe/pair](https://github.com/RyanSaxe/pair)                                                                                                                                                       |
| [`clean-and-raise-pr`](clean-and-raise-pr/SKILL.md)                       | Verify, simplify, document, rebuild history, describe, open a draft, babysit CI.  | Local                                                                                                                                                                                                   |
| [`visual-review`](visual-review/SKILL.md)                                 | Explicitly invoked; explains a subject in a repository as one HTML document.      | Local                                                                                                                                                                                                   |

`unslop` was copied from the Cursor repository on 2026-08-25. It is not linked
to the upstream file, so later upstream changes will not overwrite this copy.

`pair` lives in its own repository and has no copy here. On a machine with a
checkout at `~/Projects/pair`, the `agents` tier of `install.sh` links
`pair/` here to the checkout's `skills/pair`, and git ignores the link.
