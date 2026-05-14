# Layout and Visual Patterns

This reference is a compass, not a component API. The examples should carry most of the visual teaching.

Open `examples/design-gallery/index.html` when you need range. It shows covers, big-number slides, charts, tables, maps, code, system diagrams, timelines, decision slides, workshop prompts, appendix evidence, and closing moments.

## Working Principles

- Start with the slide's job: orient, prove, compare, explain, decide, transition, or close.
- Pick the visual form that makes that job fastest to understand.
- Use fewer words than feels comfortable on the first pass, then add only what the audience truly needs on the slide.
- Avoid using cards as the default answer. Cards are useful for peer items, but a deck made mostly of cards will feel blocky.
- Keep one deck visually coherent through type scale, color meaning, spacing, and chrome.
- Let different decks have different visual systems. The examples are deliberately varied.

## Useful Families

- **Image-led:** full-bleed cover, artifact close-up, annotated screenshot, field-photo evidence.
- **Data-led:** one-number slide, focused chart, matrix, dense table, operating ledger.
- **Technical:** architecture layers, sequence diagram, short code block, key anatomy, failure-mode grid.
- **Narrative:** editorial title, quote/thesis moment, timeline, before/after, proof mosaic.
- **Decision/workshop:** option set, tradeoff map, prompt slide, action board, closing sentence.
- **Appendix/proof:** compact evidence grid, method note, source table, backup figure.

## Template CSS

`templates/theme.css` provides a foundation: fixed Reveal canvas, typography, simple chrome, panels, metrics, figures, diagrams, tables, and code surfaces. Adapt it per deck. Do not treat the class list as the set of allowed slide designs.
