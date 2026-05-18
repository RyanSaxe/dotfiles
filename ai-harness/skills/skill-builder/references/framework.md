# Skill Framework

This is the spec for how Agent Skills are organized. It is harness-agnostic — works with Claude Code, Codex CLI, Gemini CLI, Copilot CLI, and anything else following the [Agent Skills](https://agentskills.io) standard.

## Core principles

**Outcomes are the unit of value.** A skill's job is to produce a useful, well-defined outcome — a file artifact, a git commit, a refactored codebase, a sent message, a deployed change. The conversation around the skill is ephemeral; the outcome persists. Every skill defines an Output Contract that makes its outcome verifiable.

**Align before executing when context matters.** Skills whose outcome depends on unstated user intent (presentations, refactors, design work, anything generative) should hold a structured back-and-forth before producing. Skills whose outcome is mechanical or tightly specified by inputs (validators, formatters, well-defined commits) skip alignment. Each skill describes *what it negotiates and how hard it pushes for sign-off* — there's no shared "intensity" vocabulary; the skill's own words are clearer.

**Skills are runtime self-contained.** Once a skill is built, it runs without reaching outside its own folder. At *scaffold* time, the building agent may consult shared references (see `design-system/` below). At *runtime*, the skill needs nothing the folder doesn't already contain.

**Trust the model.** Modern agents parse natural language well. Skills don't need elaborate input contracts, argument schemas, or `$ARGUMENTS` substitution. The user's request is in conversational context. A single line — *"the user may provide a target file or scope; use what's given"* — is enough. `$ARGUMENTS` / `$0` / `$1` aren't portable across all four major CLI agents anyway.

**Use the portable frontmatter subset.** Only `name`, `description`, `license`, `allowed-tools`, and `argument-hint`. Anything else is harness-specific and breaks portability.

**`SKILL.md` stays short.** Treat it like an `AGENTS.md`: a navigation index, not a manual. Push depth into `references/`. Aim for under 200 lines. The model loads `SKILL.md` every time the skill triggers — it should orient quickly and route to depth on demand.

## Folder structure

Each skill is a top-level folder. Each is independent.

```text
skills/
├── skill-builder/
│   ├── SKILL.md
│   ├── references/
│   ├── templates/
│   └── design-system/      ← taste reference (see below)
├── review/
│   ├── SKILL.md
│   ├── references/
│   ├── tools/
│   └── examples/
└── presentation/
    ├── SKILL.md
    ├── references/
    ├── starter/
    └── snippets/
```

## Anatomy of a skill folder

```text
<skill-name>/
├── SKILL.md             (required)
├── references/          (optional — depth files)
├── examples/            (optional — sample inputs/outputs)
├── templates/           (optional — files copied verbatim into output)
├── tools/               (optional — scripts the skill executes)
└── assets/              (optional — anything else the skill needs at runtime)
```

Use what you need; skip what you don't. Whatever folders the skill *does* use must be listed in the `## Layout` section of `SKILL.md` with one-line comments — so the model (and humans) see the whole skill at a glance.

## `SKILL.md` template (the slim version)

````markdown
---
name: <skill-name>
description: <one paragraph. Front-load 4–6 trigger phrases. Be slightly pushy — agents under-trigger by default. Mention what artifact it produces.>
allowed-tools: <comma-separated, optional>
argument-hint: "<inline hint, optional>"
---

# <Skill Name>

<One sentence: what it produces and why.>

## Layout

```text
<skill-name>/
├── SKILL.md             ← this file
├── references/          ← deep-dive docs (read on demand)
│   └── <file>.md        ← <when to read it>
├── examples/            ← sample inputs/outputs (delete if unused)
├── tools/               ← scripts the skill executes (delete if unused)
└── templates/           ← files copied verbatim into output (delete if unused)
```

The user may provide a target, scope, focus, or other context. Use whatever is given; ask only if a critical detail is missing and cannot be inferred.

## Alignment (delete this section if the skill executes without negotiation)

Before executing, settle the following with the user:

- <dimension 1 — e.g. audience, scope, target>
- <dimension 2 — e.g. length, depth, style>
- <dimension 3 — e.g. specific must-haves and must-avoids>

<One sentence describing how hard the skill pushes for sign-off — e.g. "confirm one ambiguous point and proceed", "propose an approach and wait for thumbs-up", "do not produce any artifact until the user has explicitly approved a written outline".>

## How to Run

<5–10 numbered steps. Concrete actions. When depth is needed, point at a reference file rather than inlining.>

## Output Contract

**Outcome:** <one sentence — what exists or changes after this skill runs.>

**Shape / schema:** <how the outcome is structured. Format + schema for files; message format + atomicity for commits; invariants for state changes; request/response shape for external side effects.>

**Verification:** <how to confirm the skill succeeded — a runnable check, a `git` command, a test suite, an API response field.>

## References

- `references/<file>` — <when to read it>
````

That's the whole template. No "Input Contract." No "Example Invocations." If a skill needs more, it pushes into references — not into `SKILL.md`.

## `design-system/` is a taste reference

`skill-builder/design-system/` exists so the agent building a new skill walks in already knowing the user's general aesthetic taste — instead of re-litigating "what should this look like" every time.

**It is consulted at scaffold time, not at runtime.** When skill-builder generates a new skill that produces a visual artifact, the building agent reads design-system to absorb preferences (colors, typography, layout sensibilities, example pages), and bakes the relevant decisions directly into the new skill's templates and code. The new skill doesn't link back to design-system; it has internalized what it needed.

**Each skill owns its full styling.** Design-system is a starting point, not a contract. A skill is free to deviate where it makes sense; nothing enforces conformance.

**Each skill owns its own output schema, fully.** Design-system has no shared schemas. If two skills happen to produce similar shapes, that's coincidence. A future tool that wants to parse multiple skills' outputs handles the differences itself.

The structure of `design-system/` and what goes inside it is `skill-builder`'s problem; see `design-system/README.md` in this skill.

## Installation

Default install location: `~/generic/dotfiles/ai-harness/skills/<skill-name>/`. This is where personal skills live, shared across projects.

Project-specific skills go in a `skills/` folder inside the project — only when the skill is genuinely tied to that project.

The skill folder is the portable unit. Any agent following the Agent Skills standard discovers it via that agent's standard discovery path; the dotfiles harness wires the personal skills folder into each agent's discovery.
