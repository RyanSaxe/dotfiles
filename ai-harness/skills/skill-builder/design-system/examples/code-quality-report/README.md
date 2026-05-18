# Code quality report

A finished artifact you might receive from a (fictional) skill named
`/quality-audit --branch=feature/payment-rewrite`.

This is **NOT** a skill folder layout — it's what a skill *produces*. See
`../README.md` for the artifact-vs-skill-folder distinction.

## How to view

Open `index.html` in any modern browser. Wifi assumed (highlight.js + Lucide
load from CDN). Zip the folder and email it; the recipient does the same.

## What this exercises in the design system

- **Semantic green/red used as backgrounds** — the diff blocks (`Before` red-soft,
  `Suggested` green-soft) are the canonical demo of `--color-positive-soft` /
  `--color-negative-soft`. The fitness dashboard never showed this pattern.
- **A 5-rung severity scale** that respects the chrome rules: red for
  critical/high (semantic negative), amber from the data-viz palette for
  medium (yellow stays reserved for active state), muted gray for low,
  blue for info.
- **Active-state yellow** on the filter chips. Click "Critical" — it fills
  with `--color-accent`, and the count badge inside flips to a translucent
  black background. This is the active-filter-chip pattern from
  `preferences.md` § Toggle / selector groups.
- **Library theme override** — `styles.css` ends with a block that remaps
  highlight.js's `.hljs-keyword` / `.hljs-string` / `.hljs-comment` / etc. to
  design-system tokens, so syntax highlighting matches the design rather
  than GitHub's default greens-and-purples.
- **Status pills** — `Open` / `Resolved` / `Won't fix` use neutral / positive /
  muted-with-strikethrough respectively. Clicking cycles them.
- **Mono font + small-caps labels + hairline borders** — the same chrome the
  fitness dashboard uses, applied to a denser content layout.

## Libraries used

- **highlight.js** (`atom-one-light` baseline) — Python syntax highlighting.
  Themed via CSS overrides at the bottom of `styles.css`.
- **Lucide** — icons (`shield-check`, `git-branch`, `file-code-2`, `x-circle`,
  `check-circle-2`, `arrow-down`, `copy`, `rotate-cw`).

## Where it deviates from defaults

- The data-viz palette is referenced for the **medium severity color**
  (`--viz-amber-3`), not for any chart. This is consistent with the
  preferences doc treating amber as "warmth / risk-tinted intensity" — the
  right semantics for "medium concern."
- `--positive-deep` / `--negative-deep` are added locally so dark
  text-on-soft-background combinations have enough contrast (light text
  on `--color-positive-soft` would not pass WCAG AA).
