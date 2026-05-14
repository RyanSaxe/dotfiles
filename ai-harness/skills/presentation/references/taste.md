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
- Title, agenda, separator, summary, conclusion, and Q&A slides may use centered or left-weighted composition because they carry less body information.
- Keep content mass visually centered in the artboard. Avoid leaving the bottom half empty unless negative space is doing real work.
- Do not put cards inside cards. Use cards, panels, and boxes only when they express grouping, comparison, state, or hierarchy.
- Avoid making every slide a grid of interchangeable blocks.

## Visual Choice

- Choose the visual that shows the relationship fastest. Do not pick from a stock list of slide types; describe the actual relationship in the user's content and design for that.
- Use charts, tables, code editors, screenshots, diagrams, icons, maps, figures, and image treatments when they explain faster than prose.
- Use best-in-class libraries, renderers, icon sets, syntax highlighters, charting tools, or diagramming tools when they materially improve the result.
- Do not hand-roll a complex visual when a stable tool can produce a more legible one.
- Do not add random visuals. Every visual should carry meaning or create useful orientation.

## Single-Slide Examples

- `examples/single-slide-examples/gallery.html` is a human review page for quickly scanning the set.
- The individual HTML files are case studies for range, spacing, hierarchy, and meaningful visuals.
- Do not copy an example unless the user explicitly asks for that exact shape.
- When building a new slide, start from the user's content relationship, then design the visual.
