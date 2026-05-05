# Visual Preferences

Written taste, in prose. Strong directional opinions, no code. Read this top to bottom before scaffolding any skill that produces a visual artifact.

The point of this document: a skill scaffolded after reading this should produce a visual artifact that *feels right* on the first try, without an alignment conversation about colors, typography, containers, or what library to use for math/code/charts/icons.

> **Reminder before you start:** the artifacts in `examples/` are *outputs of skills*, not skill-folder templates. A skill folder is much smaller than the artifacts it produces. See `README.md` § *Artifacts vs skill folders*.

## Mode

**Light only. Don't auto-flip on `prefers-color-scheme`.**

Most reports, dashboards, and decks are read in shared contexts (handed to a teammate, dropped in a doc, projected on a wall). The author and the reader should see the same thing — which means a page that looks one way on a light-mode Mac and a different way on a dark-mode Mac is a bug, not a feature.

Set `color-scheme: light` on `:root` so the browser stops applying dark-mode UA styles to form controls, scrollbars, and date pickers when the reader's OS is in dark mode. The starter `tokens/colors.css` already does this.

Dark mode is **not** a parallel design here. If a specific skill genuinely needs a dark variant — an in-IDE viewer, a terminal-adjacent tool, a presentation theme for a darkened room — the skill author writes it deliberately as a separate set of token values, opted into explicitly (a class on `<html>`, a CLI flag, an export option). Never automatic.

## Color usage — chrome

The rules in this section govern **UI chrome**: toggles, badges, deltas, status pills, buttons, headings, body text, borders. They keep the page calm so genuine signals (an active state, a successful delta, a critical error) stay loud.

They **do not** govern content-rich elements where N distinct things need to be visually separable: charts, code highlighting, multi-rung scales (severity / priority / risk). Those follow [§ Content palette](#content-palette) below — different rules, different palette.

If you find yourself making a chart, a code block, or a 5-rung scale entirely gray-with-one-accent, you are probably misapplying the chrome rules to a content area. See § Content palette → *Common mistakes*.

### Yellow / gold — *active-state accent only*

Reserved for "you are here" signals: the selected period in a date-range toggle, the current tab in a segmented control, the active filter chip, a "today" badge on a calendar.

**Never** as a primary content color. **Never** as a hero background. **Never** decorative.

*Why:* yellow's job is to make the active state pop against everything else. If yellow is also the headline color, the headline color, and the chart accent, the active state stops being distinct — which destroys the convention. One color, one job.

### Black (or near-black) — *primary emphasis*

Page titles, section headings, default-emphasis pills, totals on charts, the value when it matters more than the label. Use a soft near-black like `#0a0a0a` rather than pure `#000` — it sits more comfortably on a near-white background.

### Green and red — *semantic only*

Green for positive, success, increase, accept. Red for negative, failure, decrease, decline. Nothing else.

**Never decorative.** Don't use green because the chart needs another color. Don't use red because the icon looked sad. Once green and red are used decoratively, "this number is up 12%" loses meaning at a glance.

### Neutral grays — body and structure

A clean, slightly cool gray scale. Body text in a dark gray (~`#262626`), muted text in a mid gray (~`#737373`), separators and borders in a light gray (~`#e5e5e5`). Backgrounds at the lightest end (`#fafafa` or near-white).

The grays do most of the visual work. Color is the exception, not the rule.

## Typography

**Modern geometric sans-serif.** Inter is the default first choice; system-ui fallbacks behind it. No serifs. No display fonts. No mixing two sans families.

**Tight type hierarchy.** Three or four sizes, max. A body size, a heading size, a small-caps label size, maybe a metric/display size for big numbers. Don't proliferate; resist the urge to add `--text-md-plus` halfway through a project.

**Section labels in uppercase small-caps with letter-spacing.** Things like *"TIME UNIT"*, *"POST PERIOD"*, *"TODAY"* — uppercase, slightly tracked-out (`letter-spacing: 0.06em` or so), in a smaller size than body. This is the recurring "this is a label, not content" signal.

**Body text comfortable to read.** Line-height around 1.5. Paragraph max-width around 65 characters when the layout allows.

## Containers

**Rounded-corner cards.** Border radius around 8–12px for cards, 6px for inline pills, 4px for inputs. Not sharp corners, not aggressive blob-radius.

**Hairline borders, not heavy lines.** 1px borders in the light gray (`--color-border`). Borders define the card; they don't decorate it.

**Soft drop shadow.** A single subtle shadow (`0 1px 2px rgba(0,0,0,0.04)` or so), not multi-layered, not heavy. Shadows say "this is a separate surface" — they shouldn't say "look at me."

Cards sit on the page background; the page background is *not* a card.

## Density

**Modern simple.** Not too dense, not too airy.

A 4px spacing scale (`--space-1`=4, `--space-2`=8, ..., `--space-8`=32). Common patterns: 16–24px padding inside cards, 8–12px gaps inside a card's contents, 32–48px gaps between sections.

**Don't overdo it.** Resist the urge to add visual noise: extra dividers, busy background patterns, decorative icons next to every label. A well-spaced card with one border and one shadow is finished. Adding more makes it worse.

## Toggle / selector groups

**Pill-shaped, segmented.** Two or more options sit inside a single rounded container. Equal padding on each option. Visible only when a choice is active.

**Active option filled:**

- **Yellow** when the active state represents *"current period / current mode / current filter"* — the kind of selection that says "you're looking at this now." Black text on the yellow fill.
- **Black** when the active state represents a *primary action commitment* — *"Save"*, *"Apply"*, the chosen submit option. White text on the black fill.

**Inactive options:** transparent fill, muted gray text, no border around the individual option (only the group container has a border).

This is the rule that's easy to miscalibrate. When in doubt: yellow for "you are here," black for "do this." Never both at once.

## Content palette

The chrome rules above keep UI elements calm. They are **wrong** for content-rich areas where the *job* of color is to make N distinct things separable. Three such areas, all governed by this section:

1. **Charts** — series, sequential intensity, categorical encoding.
2. **Code highlighting** — keywords, strings, numbers, types, comments.
3. **Multi-rung scales** — severity, priority, risk, status systems with more than three states.

In all three: pure-gray-with-one-accent reads as broken, not restrained. Use the palette below; keep the chrome rules intact everywhere else.

The CSS tokens live in `tokens/colors.css` under the `--viz-*` namespace (named `viz` for brevity, but they apply to all content-rich areas, not just charts).

### Sequential ramps (5 stops, light → saturated)

For "intensity" or "magnitude" encoding — heatmaps, choropleths, density.

| Use case                                             | Ramp                                                             |
| ---------------------------------------------------- | ---------------------------------------------------------------- |
| Activity / engagement / "more is positively healthy" | green: `#f1f5f9` → `#bbf7d0` → `#4ade80` → `#16a34a` → `#14532d` |
| Generic intensity / depth / volume                   | blue: `#f1f5f9` → `#bfdbfe` → `#60a5fa` → `#2563eb` → `#1e3a8a`  |
| Warmth / risk-tinted intensity                       | amber: `#f1f5f9` → `#fde68a` → `#fbbf24` → `#d97706` → `#78350f` |

The "0 / empty" stop is always a cool pale gray (not a tinted version of the hue) so empty cells read as *absent* rather than *minimum*.

### Categorical palette (multi-series, distinguishable)

For pies / donuts / multi-line charts where you need to tell N segments apart. Pick from this set, in order:

`#2563eb` (blue) · `#06b6d4` (cyan) · `#10b981` (emerald) · `#8b5cf6` (violet) · `#f97316` (orange) · `#0ea5e9` (sky) · `#14b8a6` (teal) · `#a855f7` (purple)

**Excludes** the chrome reservations: yellow (active state) and red (semantic negative). If a chart needs more than 8 categories, the chart is wrong; group small categories into "Other."

For ordered categories that share a meaning (sleep stages, severity levels, etc.) prefer a **sequential ramp through one hue family** rather than the categorical palette — it reads as "depth" rather than "different things."

### Code highlighting

A code block is a content area, not chrome. `def`, `"foo"`, `42`, `# note`, and `MyClass` are five semantically different things; one accent color isn't enough.

**Don't hand-roll a syntax theme.** Load a stock highlight.js theme and override only what the design system needs to fix. Defaults:

- **Baseline:** `atom-one-light` (or `github-light`) via CDN. Both are light, well-tuned, and "industry-standard" enough that readers don't notice them — which is the point.
- **Required overrides** (in your own stylesheet, after the CDN link):
  - `.hljs { background: transparent; }` — so the parent surface (`var(--color-surface)`, or a `--color-positive-soft` / `--color-negative-soft` diff line) shows through.
  - `.hljs-string, .hljs-attribute, .hljs-meta-string { color: #1e3a8a; }` — atom-one-light's default is a green that's indistinguishable from the green-add diff wash. Deep blue (`--viz-blue-4`) reads on white, red-soft, and green-soft backgrounds.
- **Don't override** keywords, comments, numbers, function names, types, or built-ins. The stock theme's choices are good. Adding more rules is how I produced a monochrome code block in v1 of the code-quality-report example — see *Common mistakes* below.

If you're rendering a unified diff, the line wash (`--color-positive-soft` / `--color-negative-soft`) goes on the line container. The syntax-highlighted code sits *on top of* the wash, not inside a separate red/green text color. Word-level highlights inside a changed line should be a **translucent overlay** (`rgba(220,38,38,0.20)` / `rgba(22,163,74,0.22)`) — solid red-300 / green-300 fights the line wash for attention.

### Multi-rung scales (severity, priority, risk)

A 5-rung severity scale (`critical / high / medium / low / info`) is the canonical case. The endpoints are semantic; the middle rungs draw from the content palette so they don't collapse into gray-tonal mush.

Recipe that landed well in the code-quality-report example:

| Rung     | Color source                          | Hex       | Why                                                               |
| -------- | ------------------------------------- | --------- | ----------------------------------------------------------------- |
| Critical | semantic red, deepened                | `#b91c1c` | "This will hurt you" — strongest signal.                          |
| High     | semantic red                          | `#dc2626` | Same family, less intense — clear pairing.                        |
| Medium   | amber from the content palette        | `#d97706` | Reads as "warning" without being yellow (yellow is active-state). |
| Low      | muted gray                            | `#737373` | Genuinely background-grade.                                       |
| Info     | blue from the content palette         | `#2563eb` | Calm, neutral, "FYI."                                             |

The rules around this:

- **Don't reach for yellow** — it's reserved for active-state. Use amber (`--viz-amber-3`) for the warning rung. They look different enough that nothing collides.
- **Don't ramp through gray** for the middle rungs — gray-200 / gray-400 / gray-600 reads as "broken" not as "increasing severity." Each rung needs a distinct hue.
- **Pair the colored rung with a soft background** for badges (`#fef3c7` for medium, `#dbeafe` for info, etc.) so they sit visually consistent with the red-soft and green-soft tokens already in use.

The same approach generalizes to other multi-rung systems: priority levels (P0–P4), risk tiers, build statuses with more than `pass / fail / pending`.

### Theming the libraries with these

- **Chart.js:** pass colors via `borderColor` / `backgroundColor` / `pointBackgroundColor` per dataset. Set `Chart.defaults` for global styling (font, tooltip background = `--color-emphasis`).
- **highlight.js:** load a stock light theme via CDN, then in your stylesheet override only `.hljs { background: transparent }` and `.hljs-string` (see § Code highlighting above). Resist adding more overrides.
- **Hand-rolled SVG:** apply colors via `fill` / `stroke`; keep them as CSS variables on the SVG element so they flex with theme.
- **CSS heatmaps:** define ramp colors as `--hm-bg-1` … `--hm-bg-4` variables; the cell style keys off those.

### What still applies

- Today's cell / current period / active selection is **still** ringed or filled with `--color-accent` (yellow). The content palette doesn't override that.
- Up/down deltas, success/failure status, semantic positive/negative — **still** use `--color-positive` / `--color-negative`. Not the categorical palette.
- Gridlines, axis labels, tooltip text, finding-card titles, file paths default to neutral grays from the chrome palette.

The boundary is clear: chart series, code tokens, and scale rungs get the content palette; everything around them gets the chrome palette.

### Common mistakes

These are the failure modes from v1 attempts at the example artifacts. If you catch yourself doing one of these, you've misapplied the chrome rules to a content area.

- **Monochrome chart** — *"the chrome rules say neutral, so I made the chart gray."* No. A heatmap that ramps through gray reads as broken; categorical things need distinct hues. Pure-gray charts were the v1 of the fitness-dashboard heatmap and got rejected.
- **Single-color syntax highlighting** — *"the chrome rules say one accent, so I made keywords near-black with one accent color."* No. `def`, `"string"`, `42`, `#comment`, and `MyClass` are five semantically different categories; one color isn't enough. This was v1 of the code-quality-report and got rejected.
- **All-gray multi-rung scale with red on top** — *"the chrome rules say semantic red and otherwise muted, so I made critical red and the rest gray."* No. Middle rungs need their own hues (amber for medium, blue for info) so the scale reads as a scale, not as "one outlier in a sea of gray."
- **Word-diff highlight as solid color** — *"if a word changed, mark it bright red/green."* No — solid red-300 on a red-100 line wash creates two competing rectangles. Use a translucent overlay so the eye lands on "what changed" rather than "what's already red."

If a future skill author opens this file and the section that applies to them feels like "everything is gray," they're reading the wrong section. Send them here.

## Recommended libraries

**Don't hand-roll what an industry-standard library does well.** The design system covers layout, typography, color, spacing, and components with a distinct aesthetic. For everything else (math, code, charts, icons), reach for the libraries below and theme them via CSS to use our tokens.

Include via CDN — no need to vendor. Recipients have wifi.

| Need                       | Library                          | Notes                                                                                                                                                                                        |
| -------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Math typesetting           | **KaTeX** (`+ auto-render`)      | Faster and lighter than MathJax. Excellent defaults. Theme via CSS variables on `.katex` if you need to recolor.                                                                             |
| Code syntax highlighting   | **highlight.js**                 | Broad language support, easy CDN, low ceremony. Override the theme by remapping `.hljs-keyword`, `.hljs-string`, `.hljs-comment` etc. to your design-token values in your own stylesheet.    |
| Charts / data viz          | **Chart.js**                     | Configure colors via `borderColor` / `backgroundColor` / `pointBackgroundColor` to use design tokens. Covers line / bar / donut / scatter. Reach for D3 only when Chart.js can't express it. |
| Icons                      | **Lucide**                       | Consistent stroke weight, modern geometric, fits our type stack. Use the SVG component / Web pattern with `data-lucide="<name>"` and a single `lucide.createIcons()` call.                   |
| Slide decks                | **Reveal.js**                    | Layer CSS as Reveal's theme → your `deck.css` → per-deck `custom.css`. Default theme `white.css`; swap to a dark theme deliberately when called for.                                         |

**Why these and not others:**

- *KaTeX over MathJax* — significantly smaller, faster initial render, looks better on the first paint. MathJax's flexibility isn't worth its weight for static math in reports.
- *highlight.js over Shiki* — Shiki is more accurate but slower and heavier; highlight.js's "good enough" is better at the artifact-output bar we care about.
- *Chart.js over D3* — Chart.js gives you a beautiful chart in 10 lines; D3 gives you a custom chart in 100. We want the 10.
- *Lucide over Heroicons / Feather / Font Awesome* — Lucide's stroke weight harmonizes best with our geometric sans; it's a successor fork of Feather with broader coverage.

**Skill authors are free to override** when the user asks for something specific (a particular charting library, a brand-mandated icon set, etc.). The recommendations make "what library should I use?" a non-question for ~90% of cases.

---

If a skill needs something not covered here, deviate — but ask first whether the skill is *actually* a special case or whether the same artifact would work better following the convention.
