# Frontmatter Fields

**When to read this:** when filling in the YAML frontmatter at the top of a new `SKILL.md` and you're unsure which fields are safe to use across CLI agents.

## The portable subset (use these)

These five fields are recognized by every major harness following the Agent Skills standard. A skill that sticks to them runs identically under Claude Code, Codex CLI, Gemini CLI, and Copilot CLI.

| Field           | Required | Purpose                                                                                                  |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------- |
| `name`          | yes      | The skill's slug. Lowercase, hyphenated. Must match the folder name.                                     |
| `description`   | yes      | One paragraph that drives discovery. Front-load 4–6 trigger phrases. Mention the artifact it produces.   |
| `license`       | no       | SPDX identifier (e.g. `MIT`, `Apache-2.0`). Optional but useful when sharing skills publicly.            |
| `allowed-tools` | no       | Comma-separated list constraining which tools the skill may call. Omit to inherit the agent's defaults.  |
| `argument-hint` | no       | One-line example of how the user typically invokes the skill. Shown in autocomplete UIs.                 |

## Non-portable fields (avoid)

Each major harness has its own extensions. They work in *one* CLI and silently break portability everywhere else. Examples seen in the wild:

- **Claude Code-only:** custom hook bindings, model overrides, runtime-specific tool flags.
- **Codex-only:** `commands:` mappings, `prompts:` blocks for built-in command aliases.
- **Gemini-only:** `inputSchema` JSON schemas mirroring function-calling parameters.
- **Copilot-only:** `chatModes`, `responseFormat`, IDE-display fields.

If you find yourself reaching for one of these, ask first: can the same goal be expressed in `description` (for discovery) or in `## How to Run` (for behavior)? Those are portable. Frontmatter extensions are not.

## Naming and description tips

- **`name` matches the folder.** `skill-builder/SKILL.md` has `name: skill-builder`. Anything else confuses discovery.
- **`description` is a discovery tool, not a summary.** Agents under-trigger by default. Lead with verbs and nouns the user will actually say (*"scaffold a new skill"*, *"create a SKILL.md"*, *"audit the diff"*) — not abstract framing (*"a utility for managing skill lifecycles"*).
- **Always mention the output artifact in `description`.** "Produces a self-contained HTML report" is what tells the agent whether the skill is the right tool for the user's request.

## Why this matters

`SKILL.md` files travel between machines, between agents, and into PRs. Every non-portable field is one more reason a colleague's skill silently misbehaves on your machine. Treat the portable subset as a contract; reach outside it only with a deliberate, documented reason.
