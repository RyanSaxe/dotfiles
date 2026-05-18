# Fitness dashboard

A finished artifact you might receive from a (fictional) skill named `/fitness-report --weeks=2`. This is **NOT** a skill folder layout — it's what a skill produces.

## How to view

Open `index.html` in any modern browser. Wifi assumed (Chart.js + Lucide load from CDN).

Zip the folder and email it; recipient unzips and double-clicks `index.html`.

## What this exercises in the design system

- **Yellow as active-state accent only** — the Day/Week/Month period toggle and today's bar in the steps chart and today's cell ring in the heatmap. Nowhere else.
- **Black for primary emphasis** — page title, big metric values, hero numbers, chart line color.
- **Semantic green/red** — recovery delta (positive=green when up, negative=red when down), strain delta (negative when up, positive when down), workout status pills.
- **Small-caps section labels** — every card heading uses `.label` styling with letter-spacing.
- **Cards** — rounded `--radius-lg`, 1px hairline border, soft single-layer shadow.
- **Density** — modern simple, 4px spacing scale, comfortable not cramped.
- **Library theming** — Chart.js global defaults overridden to use design tokens (font, colors, tooltip background, point radius). Charts feel like part of the system, not an off-the-shelf widget.
- **Tabular numbers** — `font-variant-numeric: tabular-nums` on metrics and table cells so digits align.

## Libraries used

- **Chart.js** (CDN) — line / bar / donut / sparkline. Themed via `Chart.defaults` to match design tokens.
- **Lucide** (CDN) — heart, zap, moon, footprints, waves, activity, message-square-text icons. Stroke weight 2 to match our typography.

## Where it deviates from defaults

- Adds `--shadow-card-hover` for interactive lift on cards (not in the base tokens; layered as an enhancement).
- Adds a soft yellow gradient background to the "Coach's note" card to subtly tie it to the active-state palette without breaking the yellow-only-for-active rule (the card itself doesn't act as a "you are here" marker — the gradient just hints at the AI-author identity).
