# Taste and Visual Direction

These rules describe the default taste for decks made with this skill. They are not a brand system and should bend when the user's context provides stronger direction.

## Foundation

- Start from a muted warm white background and black primary text unless the user provides a brand system.
- Use accent colors for meaning: status, focus, comparison, risk, progress, or emphasis.
- Keep typography simple and deliberate. Do not use viewport-scaled type.
- Keep letter spacing at zero unless a supplied brand system requires otherwise.
- Prefer crisp spacing, confident alignment, and a small number of strong visual choices over decoration.

## Text Hierarchy

- Write slide titles as short claims that can fit on one line at a 1200px-wide review viewport.
- Write high-emphasis text to fit on one line inside its container: KPI values, focus labels, outcome statements, section titles, and callout headers.
- Let smaller supporting copy wrap when it helps explain context.
- If a line break makes the audience slow down, rewrite the text before shrinking the type.
- Avoid kickers and eyebrow labels unless they add orientation the title cannot provide.

## Layout

- Content slides should generally use a full-width title at the top and place content below.
- Title, agenda, separator, summary, conclusion, and Q&A slides should follow the default deck system unless the user has approved a different system.
- Keep content mass visually centered in the artboard and within the region it occupies. Horizontal centering is not enough; the body group should also feel vertically centered unless the slide is deliberately using asymmetry.
- Avoid leaving the top, bottom, or either side noticeably underused unless negative space is doing real work.
- Do not put cards inside cards. Use cards, panels, and boxes only when they express grouping, comparison, state, or hierarchy.
- Avoid making every slide a grid of interchangeable blocks.

## Visual Choice

- Choose the visual that shows the relationship fastest. Do not pick from a stock list of slide types; describe the actual relationship in the user's content and design for that.
- Use charts, tables, code editors, screenshots, diagrams, icons, maps, figures, and image treatments when they explain faster than prose.
- Use best-in-class libraries, renderers, icon sets, syntax highlighters, charting tools, or diagramming tools when they materially improve the result.
- Do not hand-roll a complex visual when a stable tool can produce a more legible one.
- Do not add random visuals. Every visual should carry meaning or create useful orientation.

## Visual Studies

- Full example decks are case studies for narrative flow, deck-system use, spacing, hierarchy, and meaningful content visuals.
- `examples/visual-studies/*.html` are one-shot content-slide studies for range, spacing, hierarchy, and meaningful visuals.
- `study-frame.css` and `study-frame.js` are preview harness files only. They are not deck chrome and should not be copied into generated decks.
- Do not copy an example or study unless the user explicitly asks for that exact shape.
- When building a new content slide, start from the user's content relationship, then design the visual inside the canonical deck template.
