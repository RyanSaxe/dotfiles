# Templates

Starting points for scaffolding a new skill. Copy them, drop the `.template` suffix, and fill in the placeholders.

- **`SKILL.md.template`** — the slim `SKILL.md` from the framework. Copy to `<new-skill>/SKILL.md`. Delete the `## Alignment` section if the skill is fully driven by its inputs and needs no negotiation. Keep `## Layout`, `## How to Run`, and `## Output Contract` always.
- **`reference.md.template`** — minimal scaffold for a `references/<topic>.md` file. Copy when you need depth that doesn't belong in `SKILL.md`. Each reference file should answer one question well.

The `.template` suffix is informational — it just signals "this is a starting point, not a live file." Drop it when you copy. Templates are not imported or read at runtime; they exist so a fresh agent can scaffold a new skill in seconds.
