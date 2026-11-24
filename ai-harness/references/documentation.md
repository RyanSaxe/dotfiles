# Documentation

Write documentation for a reader who was not part of the work. Keep it concise,
scannable and verified against the code. Pair this standard with `write-well`
when drafting or revising prose.

## READMEs

A README introduces the project and earns the reader's interest in about one
screen:

1. **Opening pitch:** one or two sharp sentences that say what the project does
   and why it is worth using.
2. **Visual or high-level diagram:** a screenshot, recording or architecture
   diagram that shows the shape of the system at a glance.
3. **Fast quick start:** the minimal real commands or code to try it.
4. **Links into `docs/`:** a short table or list pointing to deeper pages
   instead of duplicating manuals in the README.
5. **License** (when the repository has one).

Keep prose tight: never a dry stub and never a bloated wall of text. Leave out
status banners, roadmap promises and features that do not exist yet.

## Repository structure (Diátaxis)

For a repository with more than one documentation page, separate pages by what
the reader is trying to do, with `docs/README.md` as the index:

| Directory               | Role      | Style                                                      |
| ----------------------- | --------- | ---------------------------------------------------------- |
| `docs/getting-started/` | Tutorials | Crisp first-run steps to a working result                  |
| `docs/guides/`          | How-to    | Lean task recipes without background theory                |
| `docs/concepts/`        | Concepts  | Focused architecture and design prose, still free of fluff |
| `docs/reference/`       | Reference | Terse lookup tables, flags, schemas and defaults           |

Add `docs/contributing/` only when contributor workflow needs more than
`AGENTS.md`. Skip any directory the project does not yet need instead of adding
empty stubs.

## Diagrams in GitHub Markdown

Prefer committed light and dark SVG files inside a `<picture>` element over
fenced `mermaid` blocks. GitHub's native iOS and Android apps render Mermaid as
raw code, whereas `<picture>` SVGs render crisply everywhere in both light and
dark modes.

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/architecture-dark.svg">
  <img alt="Full description of what the diagram shows." src="assets/architecture-light.svg">
</picture>
```

Keep diagrams selective. Add one only where visual structure beats prose:

- **Typography:** use the system font stack
  (`-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif`) at
  readable sizes (`13px`–`16px` in an ~`600`–`840`-unit `viewBox`).
- **Accessibility:** set `role="img"` and an `aria-label` on `<svg>` that
  matches the `<img alt>` description.
- **Palette:** match GitHub's light and dark surfaces so both files sit
  naturally on the page:
  - Light: ink `#1f2328`, muted `#59636e`, box `#ffffff` / stroke `#b8bec6`,
    accent `#eef2fd` / stroke `#3a5bd9`.
  - Dark: ink `#e6edf3`, muted `#9198a1`, box `#0d1117` / stroke `#3d444d`,
    accent `#152042` / stroke `#6e8cf0`.
- **Visual verification:** render both `-light.svg` and `-dark.svg` to PNG on
  light and dark backgrounds and inspect the images before finishing. Confirm
  zero text clipping, zero overlapping labels or arrows, and clear contrast in
  both themes.

## Check before finishing

- Verify every command, flag, path and default against the source.
- Check that every internal link, anchor and image path resolves.
- Re-read as a newcomer and cut any sentence that announces, praises or repeats
  a nearby heading, table or example.
