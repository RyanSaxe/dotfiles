# Examples — Artifacts, not skill folders

Each folder here is a **finished artifact** — what an end user would receive after running a (fictional) skill. They are NOT skill-folder templates.

If you're scaffolding a new visual-artifact skill, do not copy these folder shapes into your new skill. Instead, **read** them to calibrate the aesthetic and quality bar; then write the skill in skill-folder shape (SKILL.md + references + templates + sometimes tools/webapp).

See `../README.md` § *Artifacts vs skill folders* for the full distinction.

## What's in here

| Folder                                             | Fictional skill                                          | What it teaches                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`fitness-dashboard/`](fitness-dashboard/)         | `/fitness-report --weeks=2`                              | Chart.js charts themed with design tokens; metric cards with sparklines; segmented period toggle; semantic positive/negative deltas; activity heatmap; sortable workouts table.                                                                                                                                                                                                                                                                                    |
| [`code-quality-report/`](code-quality-report/)     | `/quality-audit --branch=feature/payment-rewrite`        | highlight.js with custom theme overriding to design tokens; severity badges across all 5 levels; diff blocks (the canonical green/red semantic demo); side-by-side bad/good code; suggested-change cards; severity filter chips; status pills cycling on click.                                                                                                                                                                                                    |
| [`methodology-explainer/`](methodology-explainer/) | `/explain-methodology --topic="bayesian vs gradient ML"` | KaTeX math; 2-column layout (sticky sidebar TOC + article); scrollspy with yellow active-state on the current section; long-form typography (1.7 leading, 65ch measure); inline glossary; comparison grid using semantic positive/negative cell tinting; info/warning callouts; two interactive SVG figures (slider-driven Beta-binomial posterior; step-button gradient descent on a 2D loss); print stylesheet that strips controls and collapses to one column. |

## How to view

Each folder has its own `README.md` with viewing instructions. The general pattern: open `index.html` in a modern browser; wifi assumed (CDN libs).

## Portability check

Each example zips and emails cleanly:

```sh
cd <example>
zip -r /tmp/<name>.zip .
# Email /tmp/<name>.zip — recipient unzips, double-clicks index.html, it works.
```
