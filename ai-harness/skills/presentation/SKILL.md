---
name: presentation
description: Build a shareable HTML slide deck (Reveal.js) — when the user says "make a presentation", "build a deck", "make a pitch deck", "make slides for X", "explainer deck", "tech-talk slides", or wants a self-contained HTML file they can hand to someone. Produces a single-file deck rendered with reveal.js, light theme, fixed 1280×800 canvas, baked-in design tokens. Uses a sample-first calibration loop with playwright screenshots before showing the user.
---

# presentation

Builds a single-file shareable HTML slide deck using reveal.js. The deck is calibrated through deep interview + sample iteration — never spec-then-build. Three deck *variants* (`pitch`, `explainer`, `tech`) cover most use cases; new variants can be coined per invocation.

## Layout

```text
presentation/
├── SKILL.md                  ← this file
├── templates/
│   ├── theme.css             ← design tokens + chrome + variants. COPY into each deck.
│   └── deck.html.template    ← HTML skeleton with reveal init + library slots
├── references/
│   ├── variants.md           ← when to pick pitch / explainer / tech / coin a new one
│   └── layouts.md            ← catalog of layout primitives (.grid-3, .hero-metric, .flow, …)
└── examples/                 ← approved Phase-2 samples; the quality bar
    ├── pitch-adopt-skills/
    │   ├── index.html
    │   └── theme.css
    └── explainer-prompt-caching/
        ├── index.html
        └── theme.css
```

The deck the skill produces is structurally similar to either example. Open one in a browser before drafting if you've forgotten what "good" looks like.

## Alignment

Each invocation of this skill is a working session, not an input-driven render. Settle the following with the user before drafting any slides:

- **Topic and angle** — what's the one-sentence thesis the audience walks away with?
- **Audience and context** — who reads / sits in the room? Internal eng? Exec? External? Read alone or presented?
- **Variant** — pitch (persuasive, dramatic), explainer (academic, longform), tech (dense, code-forward), or something new the conversation surfaces. See [`references/variants.md`](references/variants.md).
- **Length** — rough slide count (8 / 10 / 15) and whether timing matters.
- **Inputs** — does the user have notes, a doc, a Slack thread to draw from? Or is it conversation-only?
- **Constraints** — required content, banned framings, tone limits.

Don't ask all at once. Adapt rounds based on what each answer reveals. The single biggest failure mode of this skill is jumping to slides before knowing what the deck is *for*.

## How to Run

### Phase 1 — Discover

Drive the conversation above. End when you know enough to draft slides the user would recognize as their intent.

### Phase 2 — Draft and self-review

1. Pick a working directory under `/tmp/<deck-name>/`. Copy `templates/theme.css` and `templates/deck.html.template` (rename to `index.html`) into it.
2. Set `<body class="deck-<variant>">` on the new deck.
3. Write the slides. Lean on the catalog in [`references/layouts.md`](references/layouts.md) — pick layout primitives, don't invent. Each slide is `<section>` containing `.slide-head` (kicker + title), `.slide-body` (content), `.slide-foot` (deck name + slide count).
4. **Self-review with screenshots before showing the user.** Run `uv run --script ~/.claude/skills/skill-builder/tools/screenshot.py /tmp/<deck-name>/index.html` and read the resulting PNGs. Catch obvious breakage (overflow, mis-centered headlines, kicker collisions) yourself; iterate until it looks right.
5. Show the user. React to feedback. Iterate.

### Phase 3 — Approve

When the user signs off, the deck is done. The folder at `/tmp/<deck-name>/` is the deliverable; user can `zip -r deck.zip /tmp/<deck-name>` and send.

If the deck represents a new pattern worth keeping, copy it into `examples/` for future calibration.

## Output Contract

**Outcome:** a working directory `/tmp/<deck-name>/` containing `index.html` + `theme.css`, openable by double-clicking `index.html` in a browser. Wifi assumed (CDN libraries are fine).

**Shape / schema:**

- `index.html` is a single self-contained file linking `theme.css` (relative path) and reveal.js + optional libraries (Chart.js / KaTeX / highlight.js) via CDN.
- `<body class="deck-<variant>">` opts into one of the variants defined in `theme.css`.
- Each `<section>` has the three-row chrome: `.slide-head` (kicker + h1/h2), `.slide-body` (content), `.slide-foot` (deck name + slide count). Slide count appears ONLY in foot.
- Reveal init pins the canvas at `width: 1280, height: 800, margin: 0, center: false`.
- Layout primitives come from the catalog in [`references/layouts.md`](references/layouts.md); don't invent new ones unless the user's content demands it.
- Theme.css is *copied* into the deck folder (not symlinked, not `@import`ed from skill-builder).

**Verification:**

```sh
~/.claude/skills/skill-builder/tools/verify.sh ~/.claude/skills/presentation/
uv run --script ~/.claude/skills/skill-builder/tools/screenshot.py /tmp/<deck-name>/index.html
```

The verify script confirms the skill folder is structurally sound. The screenshot script confirms the deck actually renders without layout breakage at 16:9, wide, and portrait viewports.

## References

- [`references/variants.md`](references/variants.md) — picking pitch vs explainer vs tech, or coining a new variant.
- [`references/layouts.md`](references/layouts.md) — catalog of layout primitives (cards, grids, hero metrics, flow diagrams, prompt diagrams, pull-quote moments).
- [`templates/theme.css`](templates/theme.css) — the design tokens, chrome, and variant overrides. Read top to bottom before drafting your first deck.
- [`templates/deck.html.template`](templates/deck.html.template) — the HTML skeleton.
- [`examples/`](examples/) — two approved decks. Open in a browser to recalibrate.
