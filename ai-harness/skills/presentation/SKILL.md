---
name: presentation
description: Build a shareable HTML slide deck (Reveal.js) when the user says "make a presentation", "build a deck", "make a pitch deck", "make slides", "explainer deck", "discussion deck", "townhall deck", or wants a self-contained HTML file they can present or send. Produces a single named HTML file with inline CSS, a light theme, fixed 1280x800 canvas, and screenshot-reviewed polish.
---

# presentation

Builds a single-file shareable HTML slide deck using Reveal.js. This is a working session skill: calibrate through a critical interview, draft visually, self-review with screenshots, then iterate with the user.

## Layout

```text
presentation/
├── SKILL.md
├── templates/
│   ├── theme.css             ← reusable source CSS; inline into final HTML
│   └── deck.html.template    ← single-file HTML skeleton with CSS slot
├── references/
│   ├── variants.md           ← figuring out register, footer metadata, and section markers
│   └── layouts.md            ← layout primitives and visual patterns
└── examples/
    ├── executive-discussion/
    │   └── executive-portfolio-review.html
    ├── product-update/
    │   └── product-checkout-update.html
    └── townhall-update/
        └── platform-townhall.html
```

The examples are fictional calibration decks. Open at least one before drafting if you need to re-center on the expected quality bar.

## Critical Interview

Do not jump straight to slides. Use `request_user_input` when available for real tradeoffs; ask direct questions only when multiple choice would be awkward.

Resolve these before drafting:

- **Audience and room:** who is present, how senior, read-ahead vs. live voiceover, and what they already believe.
- **Purpose:** what the deck must accomplish, stated in the user's language rather than chosen from a fixed taxonomy.
- **Thesis:** the one sentence the audience should retain.
- **Content inventory:** the full raw material the user already knows: facts, examples, tensions, decisions, constraints, anecdotes, data points, and half-formed arguments that need to be distilled.
- **Narrative shape:** current state, tension, recommendation, examples, operating model, ask, risks, appendix.
- **Length and timing:** target slide count, which material can move to appendix, and whether detail will be voiced over.
- **Inputs:** docs, notes, existing decks, screenshots, data, required examples.
- **Constraints:** banned wording, sensitive topics, required terms, brand/style preferences, and shareability needs.
- **Register and footer metadata:** how the deck should feel in this specific room, and what stable deck-level label belongs in the footer.
- **Slide/speaker split:** what must be legible on the slide vs. what the presenter will say.

End discovery only when you can describe the deck's goal, audience, constraints, rough order, register, shared footer label, and what "good" means for this user. These are not menu selections; they are judgments to work out from the user's context.

## How to Run

1. Pick a working directory under `/tmp/<deck-slug>/`.
2. Copy `templates/deck.html.template` to `<deck-slug>.html`.
3. Copy `templates/theme.css` into the `<style>` slot in the HTML. The final deliverable is a single named HTML file, not `index.html` plus `theme.css`.
4. Work out the deck register and shared footer label from the interview. Do not force fixed modes like "pitch" or "explainer"; see `references/variants.md`.
5. Draft slides with the three-row chrome:
   - `.slide-head` with a short kicker and short title
   - `.slide-body` with visual structure
   - `.slide-foot` with deck title, the same deck-level footer label on every slide, and `N / Total`
6. Use `references/layouts.md` for patterns. Prefer adapting a primitive over inventing a one-off layout.

## Quality Bar

Every deck should be scan-ready, even if the audience is technical.

- Keep titles short and specific.
- Avoid paragraph-heavy slides; move detail to speaker track or appendix.
- Prefer diagrams, flows, proof cards, comparisons, and summary statements over text blocks.
- Use icons, labels, and visual grouping to make the structure obvious.
- Do not put cards inside cards.
- Section dividers should feel like transitions, not content slides.
- Appendix material must be visually and narratively separate from the main recommendation, using dividers, kickers, and slide content rather than changing the shared footer label to "Appendix."
- If a slide feels crowded, split it or simplify it before shrinking type.

## Self-Review

Before showing the user, run screenshots and critique the deck yourself:

```sh
uv run --script ~/.claude/skills/skill-builder/tools/screenshot.py /tmp/<deck-slug>/<deck-slug>.html
```

Review 16:9, wide, and portrait renders. Fix:

- clipped or overlapping text
- long titles
- weak visual hierarchy
- dense blocks that are hard to scan
- charts/diagrams with unclear emphasis
- appendix slides that read like main-story slides
- footer/slide-count mistakes, especially footer labels that change by section

Then show the user the deck and ask for critique. When feedback is broad, first propose a slide-level plan; when feedback is specific, implement and re-render.

## Output Contract

- Deliver one file named `<presentation-name>.html`.
- The file links Reveal.js and optional libraries by CDN, but deck CSS is inline.
- Reveal is initialized at `width: 1280`, `height: 800`, `margin: 0`, `center: false`.
- The deck is usable by opening the HTML directly in a browser.
- Keep reusable CSS in `templates/theme.css`; do not require recipients to zip a folder.

## References

- `references/variants.md` — figuring out register, shared footer language, and section markers.
- `references/layouts.md` — visual primitives and when to use them.
- `templates/theme.css` — reusable source CSS to inline into generated decks.
- `templates/deck.html.template` — single-file HTML skeleton.
- `examples/` — fictional calibration decks for quality and variety.
