---
name: skill-builder
description: Scaffold a new Agent Skill — when the user says "create a skill", "make a new skill", "scaffold a skill", "build a skill-builder skill", "new SKILL.md", "add an agent skill", or wants to package a workflow as a reusable skill. Produces a self-contained skill folder (SKILL.md + references + templates + optional design-system internalization) that conforms to the harness-agnostic Agent Skills framework.
license: MIT
---

# Skill Builder

Scaffolds new Agent Skills that conform to the framework defined in [`references/framework.md`](references/framework.md). Every other skill in this dotfiles harness is built using this one.

## Layout

```text
skill-builder/
├── SKILL.md                     ← this file
├── references/                  ← deep-dive docs (read on demand)
│   ├── framework.md             ← canonical spec for the Agent Skills format
│   ├── frontmatter-fields.md    ← portable subset of YAML frontmatter
│   ├── output-contracts.md      ← catalog of outcome shapes + verification recipes
│   └── alignment-patterns.md    ← when/how to use the optional Alignment phase
├── templates/                   ← starter files copied when scaffolding
│   ├── SKILL.md.template        ← slim SKILL.md skeleton
│   ├── reference.md.template    ← scaffold for a references/<file>.md
│   └── README.md                ← short note about the templates
├── tools/                       ← helper scripts the skill executes
│   └── verify.sh                ← structural check on a new skill folder
└── design-system/               ← TASTE REFERENCE (scaffold-time only, never imported at runtime)
    ├── README.md                ← role and rules of design-system; artifact-vs-skill-folder distinction
    ├── preferences.md           ← written taste in prose, incl. Content palette + Recommended libraries
    ├── tokens/                  ← starter CSS custom-property files
    │   ├── colors.css
    │   ├── typography.css
    │   └── layout.css
    └── examples/                ← finished artifact-folders (NOT skill-folder templates)
        ├── README.md
        ├── fitness-dashboard/        ← Chart.js dashboard archetype
        ├── code-quality-report/      ← highlight.js report archetype
        └── methodology-explainer/    ← KaTeX longform article archetype
```

## Alignment

Building a skill is a working session, not a form-fill. Before any of the new skill's files are written, settle the following with the user:

- **Skill identity** — kebab-case name, one-sentence description, install location.
- **Artifact archetype** — what's produced and how. Visual artifact (HTML page, dashboard, report)? Structured text (commit message, log entry, formatted output)? Code change (refactor, patch)? External side effect (PR, Slack, API call)?
- **Trigger surface** — which phrases the user will say to invoke; what context the skill should pull from.
- **Success criteria** — what makes the artifact "good" for *this* user. Almost never settle-able in prose; calibrated via sample artifacts in Phase 2.
- **Whether the new skill itself needs an `## Alignment` section** — i.e. does each invocation need negotiation, or is the skill input-driven?

**Threshold (high push):** *Do not write any of the new skill's files until at least one sample artifact has been explicitly approved by the user.* Sample artifacts are throwaway and cheap; the skill folder is what we're calibrating toward. Outlines and prose specs do not count as approval — only a concrete, real, rendered or drafted artifact does.

This loop applies to every archetype, not just visual. For a commit-message skill, the sample is a drafted commit message. For a refactor skill, it's a sample diff. See [`references/alignment-patterns.md`](references/alignment-patterns.md) § *Calibration loop* for worked examples in both visual and non-visual cases.

## How to Run

Five phases. The first three are a real working session with the user; the last two are mechanical. The transition from Phase 2 to Phase 3 is the moment the user has signed off on a concrete sample.

### Phase 1 — Discover (intensive)

1. Drive an in-depth working conversation with the user — plan-mode-level depth. By the end of Phase 1 you should know enough that the first sample artifact has a real chance of landing close. Phase 2's iteration covers "close → right"; Phase 1 has to make it close.
2. Use AskUserQuestion liberally. Multiple rounds are normal and expected. Adapt the questions to the archetype; at minimum cover:
   - **Identity** — kebab-case name, one-line description, install location.
   - **Trigger** — when should this fire? What phrases? What context does the skill pull from (conversation only, current repo, a specific scope)? Is the skill project-specific or generic across any environment?
   - **Audience** — who reads / uses what comes out? The user? Their team? An external recipient?
   - **Outcome** — what should exist or change after each run? What does success look like concretely, with examples?
   - **Failure** — what would the user reject? Bad versions they've seen elsewhere and disliked?
   - **Reference artifacts** — anything in the user's mind (a doc, a tool's output, a colleague's style) that captures the feel they want?
   - **Constraints** — required libraries, banned conventions, format mandates, tone limits.
   - **Iteration model** — does each invocation need negotiation (the new skill has its own `## Alignment`), or is it fully input-driven?
3. Don't ask everything at once. Adapt based on what each round reveals. Keep going until the user signals "let's see a draft" or until you genuinely know enough to draft something the user would recognize as their intent. Skipping this phase to get to samples faster is the single biggest failure mode of this skill.

### Phase 2 — Calibrate via samples

1. Pick 1–3 hypothetical inputs that the future skill might handle, drawn from what the user described in Phase 1. Mock up inputs where needed — the goal is for the user to react to what the skill *would produce*, not to validate any specific real-world input. (The skill may be generic across many environments; don't assume there's a current repo, file, or diff to pull from.)
2. Produce sample artifact(s) as if the skill were already built and called on those inputs. For visual: scaffold an actual rendered page in `/tmp/<sample-name>/` (read [`design-system/README.md`](design-system/README.md) and [`design-system/preferences.md`](design-system/preferences.md) before drafting). For non-visual: draft inline (a commit message, a sample diff, a log line — whatever the skill would produce).
3. Show the samples. React to feedback. Iterate. Each iteration is cheap; the skill folder is the expensive thing we're calibrating toward.
4. Continue until the user explicitly approves a sample. **No skill files yet.** See [`references/alignment-patterns.md`](references/alignment-patterns.md) § *Calibration loop* for worked iterations.

### Phase 3 — Extract preferences

1. Name what made the approved sample(s) good. For visual: which tokens, layouts, library choices, palette decisions. For non-visual: format spec (length, structure), tone, conventions, good/bad pairs.
2. Decide where each preference lives in the eventual skill folder: tokens baked into a `templates/` stylesheet (visual); format spec written into `references/format.md` (non-visual); approved samples preserved verbatim in `examples/` (both).

### Phase 4 — Scaffold

1. Pick the install location (default: `~/generic/dotfiles/ai-harness/skills/<skill-name>/`; project-local `skills/` only when the skill is genuinely tied to one project). Create the skill folder. The folder shape is settled by the conversation in Phases 1–3 and is flexible — but in practice every skill includes more than just `SKILL.md`. **`examples/` is generally expected** (the place where Phase 2's approved samples graduate to live alongside the skill). Other folders are situational: `references/` when SKILL.md would otherwise grow past 200 lines, `templates/` when the skill scaffolds files from a known shape, `tools/` when the skill needs a runnable helper script.
2. Write the new skill's `SKILL.md`, baking in the preferences extracted in Phase 3. The four reference docs in this skill (framework, frontmatter-fields, output-contracts, alignment-patterns) are on-demand depth — pull whichever one you have a specific question about; don't walk through them in order.
3. **If the skill produces a visual artifact, internalize the design-system tokens.** The pattern (used by all three example artifacts in `design-system/examples/`): **copy** the relevant CSS custom properties from `design-system/tokens/` into a `:root {}` block inside the new skill's own stylesheet or template `<style>`, and **adapt** — drop tokens the skill won't use, rename or restructure where it makes the skill's CSS clearer. The point is a *snapshot* of values, not a live `<link>` or `@import` — so the new skill is runtime-decoupled from `skill-builder/`.
4. Promote the approved Phase-2 samples into the new skill's `examples/` folder. They are real artifacts the skill produced and the user signed off on — the strongest possible documentation of the quality bar.

### Phase 5 — Verify

1. Run `tools/verify.sh <new-skill>/`. It checks structural invariants — frontmatter parses, name matches folder, required sections present, no runtime coupling back to `skill-builder/`. Behavioral correctness was the job of Phases 1–4; most skills require conversation to actually exercise, so triggering them in this session isn't a meaningful test. Once `verify.sh` passes and the calibration is baked in, the skill is done.

## Output Contract

**Outcome:** a new directory at `<install-location>/<skill-name>/` containing — at minimum — a `SKILL.md` that satisfies the framework, plus `examples/` with the approved Phase-2 samples. Other folders (`references/`, `templates/`, `tools/`, `assets/`) are present only when used.

**Shape / schema:**

- `SKILL.md` exists, parses as Markdown with valid YAML frontmatter.
- Frontmatter uses only the portable subset (`name`, `description`, `license`, `allowed-tools`, `argument-hint`).
- `name` matches the folder name.
- `description` includes 4+ trigger phrases and mentions the output artifact.
- `## Layout` section mirrors the actual folder contents.
- `## Output Contract` section names an outcome, a shape/schema, and a verification recipe.
- `## How to Run` section contains numbered steps.
- `## Alignment` section is present *or* absent — never empty.
- `SKILL.md` is under 200 lines.
- If the skill produces a visual artifact: no file in the new skill's folder contains the strings `skill-builder/design-system` or `../skill-builder/`.

**Verification:**

```sh
tools/verify.sh <new-skill>/
```

The script reports `ok` / `warn` / `FAIL` per check and exits non-zero if any check fails. See `tools/verify.sh` for the full check list.

## References

- [`references/framework.md`](references/framework.md) — canonical spec. Read first when anything is ambiguous.
- [`references/frontmatter-fields.md`](references/frontmatter-fields.md) — read when filling in the new skill's YAML frontmatter.
- [`references/output-contracts.md`](references/output-contracts.md) — read when deciding what shape the new skill's outcome should take.
- [`references/alignment-patterns.md`](references/alignment-patterns.md) — read for the Calibration loop pattern (Phase 2) and for deciding whether the new skill needs its own `## Alignment` section.
- [`design-system/README.md`](design-system/README.md) — read at scaffold time when the new skill produces a visual artifact. Never linked from the new skill at runtime.
- [`templates/`](templates/) — starting points to copy when scaffolding.
- [`tools/verify.sh`](tools/verify.sh) — structural check on a new skill folder. Run in Phase 5.
