# Methodology explainer

A finished artifact you might receive from a (fictional) skill named
`/explain-methodology --topic="bayesian vs gradient ML"`.

This is **NOT** a skill folder layout — it's what a skill *produces*. See
`../README.md` for the artifact-vs-skill-folder distinction.

## How to view

Open `index.html` in any modern browser. Wifi assumed (KaTeX / highlight.js
/ Lucide load from CDN). Print with ⌘P / Ctrl-P — `print.css` will collapse
the layout to one column, drop interactive controls, and adjust type for
paper.

## What this exercises in the design system

This is the **publication archetype**, distinct from the dashboard
(fitness) and report (code-quality) examples. It pushes typography and
content patterns the others don't.

- **Long-form typography**: relaxed line-height (1.7), 65-character measure,
  a true type hierarchy from `--text-display` page title down to small-caps
  labels. The body section length tests that the design system reads
  comfortably at length, not just in card-sized chunks.
- **Sticky TOC with scrollspy active state** — the canonical "you are
  here" yellow on the section currently in view. As you scroll, the active
  TOC link updates; this is the same pattern as the period segmented
  toggle in fitness, applied to navigation.
- **KaTeX math** sitting on a tinted strip so equations read as a distinct
  surface, not body text. Inline `$\theta$` flows with the surrounding
  line.
- **Code highlighting following the Content palette recipe**: load
  atom-one-light, override only `.hljs { background: transparent }` and the
  string color (`#1e3a8a`) so strings don't collide with potential green
  callouts. No keyword/comment/number overrides — the stock theme handles
  those well.
- **Callouts** (info / warning) using `--info-soft` / `--warn-soft`
  backgrounds with a 4px colored left border. Demonstrates that the Content
  palette's amber and blue have soft-tint backgrounds, the same way
  `--color-positive-soft` / `--color-negative-soft` work for the chrome
  rules.
- **Comparison grid** with semantic-positive / semantic-negative / neutral
  cells — the canonical real-world use of `--color-positive-soft` /
  `--color-negative-soft` as cell tinting (the code-quality diff blocks
  use them at the line level; here they tint table cells).
- **Two interactive SVG figures** with sliders + buttons themed to the
  design system. The figures use the Content palette's categorical hues
  (cyan / orange / violet) for the three Beta curves, and use `--accent`
  yellow as the "current point" ring on the gradient-descent path.
- **Print stylesheet** (`print.css`) that strips interactive controls,
  collapses to one column, and adds `(URL)` after external links so a
  paper reader can follow them.

## Libraries used

- **KaTeX** (with auto-render extension) via CDN — math typesetting.
- **highlight.js** (atom-one-light baseline) via CDN — for the small
  Python snippet. Themed per the design-system Content palette recipe.
- **Lucide** via CDN — icons.

## Where it deviates from defaults

- The two interactive figures are **hand-rolled SVG**, not Chart.js. The
  design-system recommendation is "reach for D3 only when Chart.js can't
  express it" — but Chart.js doesn't have a clean way to drive a custom
  loss surface or a slider-bound posterior overlay. SVG with
  `createElementNS` is the right primitive for these. Chart.js would still
  be the right pick if these were standard line/bar/donut charts.
- The TOC is a 2-column layout with a sticky sidebar. Below 900px it
  collapses to a top section (no margin notes / 3-column variant — that
  was on the table but kept simple to keep the example readable).
