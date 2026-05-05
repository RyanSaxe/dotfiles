# Design System

A *taste reference* for visual artifacts produced by skills. Read at scaffold time, not at runtime.

## What this is

When `skill-builder` scaffolds a new skill that produces a visual artifact (HTML report, dashboard, presentation, status page, anything rendered), the building agent reads this folder, absorbs the preferences, and bakes the relevant decisions directly into the new skill's templates and code.

The new skill **never references `design-system/` at runtime.** Once scaffolded, it owns its full styling. Tokens, fonts, color choices — internalized, not imported.

## Artifacts vs skill folders — read this first

Two things in this codebase are called "self-contained." They are not the same. Conflating them produces wrong design choices.

|                      | What it is                                                                                                            | "Self-contained" means                                                                                       | Lives in                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| **Skill folder**     | What the *agent* reads to do its job (SKILL.md + references + templates + sometimes a webapp like `review`'s viewer). | The skill runs anywhere with no external dotfiles dependency. Minimal, structured.                           | `<skill-name>/`                                |
| **Artifact example** | What an *end user* receives — a finished deliverable. May use JS, CDN libraries, multiple files.                      | The folder zips, emails, and opens by double-clicking `index.html`. **Wifi is assumed** — CDN libs are fine. | `skill-builder/design-system/examples/<name>/` |

The artifact examples in `examples/` are **not** templates for skill folders. They are *reference outputs* — the quality bar future visual-artifact skills should aim for. When scaffolding a skill, do not copy `examples/<x>/` shape into `<new-skill>/`. Read the example to calibrate aesthetic and quality; then write the skill in skill-folder shape.

Same word, two scopes:

- A **skill folder** is self-contained so the *agent* can run the skill anywhere.
- An **artifact example** is self-contained so the *recipient* can open it from a zip.

## Why skills internalize instead of linking

- **Skills stay self-contained.** A skill folder must run without reaching outside itself (framework rule). If `presentation/` symlinked back to `skill-builder/design-system/tokens/`, every skill would be coupled to skill-builder's lifecycle. Brittle.
- **Skills can deviate.** The taste reference is a starting point, not a contract. A scientific-figures skill might need a different palette; a brand-pitch skill might override typography entirely. Nothing here enforces conformance.
- **Walking-in pre-aligned.** Without this folder, every visual-artifact skill re-litigates colors, fonts, spacing, and library choices from scratch. With it, the agent already knows: *"light mode default, yellow as active state only, geometric sans-serif, rounded cards, default to KaTeX/Chart.js/highlight.js/Lucide."* The conversation stays focused on the skill's actual domain.

## How to use it (for the building agent)

1. Read [`preferences.md`](preferences.md) end to end — including § *Content palette* and § *Recommended libraries*. It's prose, not code; internalize the *why* alongside the rule.
2. Skim the three `tokens/` files. Note the semantic names (`--color-accent`, not `--color-yellow-500`) — those names should survive into the new skill's CSS.
3. Open one or two `examples/<name>/index.html` in a browser to see how the tokens render in real polished context. Note what each example uses libraries for vs hand-rolls.
4. Copy whichever tokens the new skill needs into the new skill's own templates. Adapt freely. Drop tokens the skill won't use.
5. Reference the same default libraries (KaTeX / highlight.js / Chart.js / Lucide) in the new skill's output templates unless the user has asked for something else.
6. Do **not** add a `<link>` or `@import` from the new skill back to this folder.

For non-visual skills (commit messages, log formatters, refactors, etc.), the same calibration loop applies — produce sample artifacts during Phase 2, iterate on user feedback, bake approved samples into the new skill's `examples/`. There's no design-system equivalent for non-visual taste because non-visual artifacts are short enough that per-skill examples suffice. See [`../references/alignment-patterns.md`](../references/alignment-patterns.md) § *Calibration loop* for both visual and non-visual worked examples.

## Layout

```text
design-system/
├── README.md           ← this file
├── preferences.md      ← written taste, in prose; includes recommended-libraries table
├── tokens/             ← CSS custom-property starter files
│   ├── colors.css
│   ├── typography.css
│   └── layout.css
└── examples/           ← finished artifact-folders (NOT skill-folder templates)
    ├── README.md
    ├── fitness-dashboard/        ← Chart.js dashboard, what /fitness-report would output
    ├── code-quality-report/      ← highlight.js review report, what /quality-audit would output
    └── methodology-explainer/    ← KaTeX longform article, what /explain-methodology would output
```

The example topics are deliberately *unrelated* to any planned skill — the existing `review` and `presentation` plans, plus anything else likely to get built. That keeps the example a *reference* rather than a regression target: when a real skill gets built later, its design is informed by the example's quality bar but not constrained to its specific shape.
