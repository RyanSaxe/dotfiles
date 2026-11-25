---
name: repo-docs
description: Use when writing, reorganizing or auditing a repository's README.md, docs/ tree, architecture documentation or GitHub Markdown diagrams. Covers README structure, Diátaxis layout, solution-focused architecture docs and light/dark SVG diagrams. Pair with write-well for writing and revising prose.
---

# Repository documentation

Write documentation for a reader who was not part of the work. Keep it short,
easy to scan and accurate against the code. Pair this skill with `write-well`
when writing or revising prose.

## READMEs

A README is the front door to the repository:

1. **What it is:** one or two plain sentences saying what the project does and
   why it exists.
2. **Overview visual:** a screenshot, recording or architecture diagram showing
   how it fits together.
3. **Quick start:** the minimal commands or code to try it.
4. **Links to `docs/`:** a short index pointing to deeper pages instead of
   duplicating them here.

Keep a root `LICENSE` file (GitHub shows it in the sidebar) and skip a redundant
`## License` section unless a special notice, such as a Fan Content Policy, is
required. Leave out status banners, roadmap promises and features that do not
exist yet.

## Repository structure (Diátaxis)

For a repository with more than one documentation page, separate pages by what
the reader is trying to do, with `docs/README.md` as the index:

| Directory               | Role      | Contents                                       |
| ----------------------- | --------- | ---------------------------------------------- |
| `docs/getting-started/` | Tutorials | First-run steps to a working result            |
| `docs/guides/`          | How-to    | Task-focused recipes without background theory |
| `docs/concepts/`        | Concepts  | Architecture and design explanations           |
| `docs/reference/`       | Reference | Lookup tables, flags, schemas and defaults     |

Add `docs/contributing/` only when contributor workflow needs more than
`AGENTS.md`. Skip any directory the project does not need yet instead of adding
empty stubs.

`docs/concepts/architecture.md` explains the architecture of the solution, not a
folder, file or module inventory. Cover the problem being solved, the main
design choices, how data and control move across major components and why the
boundaries and invariants exist. Put directory maps, module lists and CLI flag
tables in `docs/reference/` or `docs/contributing/`.

Never list a repository's lint rules, import-boundary rules or static-check
catalogs in `docs/` (including `docs/contributing/`). CI and config files are
the source of truth for contributors.

## Diagrams in GitHub Markdown

Use committed light and dark SVG files inside a `<picture>` element instead of
fenced `mermaid` blocks. GitHub's iOS and Android apps show Mermaid as raw code,
while `<picture>` SVGs render everywhere in both light and dark modes.

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/architecture-dark.svg">
  <img alt="Full description of what the diagram shows." src="assets/architecture-light.svg">
</picture>
```

Add a diagram only when visual layout explains a relationship better than prose:

- **Typography:** use the system font stack
  (`-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif`) at
  readable sizes (`13px`–`16px` in a `600`–`840`-unit `viewBox`).
- **Accessibility:** set `role="img"` and an `aria-label` on `<svg>` that
  matches the `<img alt>` text.
- **Palette:** match GitHub's light and dark backgrounds:
  - Light: ink `#1f2328`, muted `#59636e`, box `#ffffff` / stroke `#b8bec6`,
    accent `#eef2fd` / stroke `#3a5bd9`.
  - Dark: ink `#e6edf3`, muted `#9198a1`, box `#0d1117` / stroke `#3d444d`,
    accent `#152042` / stroke `#6e8cf0`.
- **Visual check:** render both `-light.svg` and `-dark.svg` to PNG on light
  (`#ffffff`) and dark (`#0d1117`) backgrounds and inspect the images before
  finishing. Check for clipped text, overlapping labels or arrows, and low
  contrast in both modes.

## Check before finishing

- Check every command, flag, path and default against the source.
- Check that every internal link, anchor and image path resolves.
- Re-read as a newcomer and cut any sentence that merely repeats a nearby
  heading, table or example.
