---
name: presentation
description: Build a shareable HTML slide deck when the user says "make a presentation", "build a deck", "make a pitch deck", "make slides", "explainer deck", "discussion deck", "townhall deck", or wants a self-contained HTML file they can present or send. Produces one polished browser-openable HTML file, usually with Reveal.js.
---

# presentation

Builds a shareable HTML slide deck. This is a working-session skill: interview critically, draft visually, review screenshots, and iterate.

## Layout

```text
presentation/
|-- SKILL.md
|-- templates/
|   |-- theme.css
|   `-- deck.html.template
|-- references/
|   |-- variants.md
|   `-- layouts.md
`-- examples/
    |-- gallery/
    |   |-- agendas/
    |   |-- metrics/
    |   |-- risks/
    |   |-- roadmaps/
    |   |-- separators/
    |   |-- spotlights/
    |   |-- statuses/
    |   |-- titles/
    |   |-- transitions/
    |   `-- index.html
    |-- design-gallery/
    |   `-- index.html
    |-- image-led-narrative/
    |   `-- coastal-launch-field-notes.html
    |-- operating-review/
    |   `-- reliability-operating-review.html
    `-- technical-explainer/
        `-- cache-boundary-explainer.html
```

The examples are visual calibration artifacts, not templates. Open `examples/gallery/index.html` before drafting when you need to re-center on variety, hierarchy, and range.

## Critical Interview

Do not jump straight to slides. Use `request_user_input` when available for real tradeoffs; ask direct questions only when multiple choice would be awkward.

Resolve these before drafting:

- **Audience and room:** who is present, how senior, read-ahead vs. live voiceover, and what they already believe.
- **Purpose:** what the deck must accomplish, stated in the user's language.
- **Thesis:** the one sentence the audience should retain.
- **Content inventory:** facts, examples, tensions, decisions, constraints, anecdotes, data points, and half-formed arguments.
- **Narrative shape:** how the audience should move from current belief to the intended action or understanding.
- **Length and timing:** target slide count, appendix needs, and what will be spoken instead of written.
- **Inputs:** notes, docs, existing decks, screenshots, data, brand requirements, and required examples.
- **Constraints:** banned wording, sensitive topics, required terms, shareability needs, and style preferences.
- **Visual stance:** image-led, editorial, data-heavy, technical, workshop, executive, or another concrete direction derived from the room.
- **Slide/speaker split:** what must be legible on the slide vs. what the presenter will say.

End discovery only when you can describe the deck's goal, audience, constraints, rough order, visual stance, and what "good" means for this user.

## How to Run

1. Pick a working directory under `/tmp/<deck-slug>/`.
2. Copy `templates/deck.html.template` to `<deck-slug>.html`.
3. Copy `templates/theme.css` into the `<style>` slot in the HTML, then add deck-specific CSS as needed.
4. Keep the final deliverable as one named HTML file unless the user explicitly wants a folder of assets.
5. Draft the deck around slide jobs and visual hierarchy, not around a fixed component list.
6. Use `references/layouts.md` and `examples/gallery/index.html` to broaden possibilities when a slide starts looking like a generic card grid.

## Deck Structure

Default to this deck arc unless the user's context clearly needs a different shape:

```text
title -> agenda -> separator for agenda item 1 -> content -> separator for agenda item 2 -> content -> ... -> final slide
```

- Keep agendas to 5 items or fewer.
- Use a separator before each major agenda section. Include a short section label and, when helpful, a minimal subtitle.
- Choose the final slide intentionally: summary, conclusion, decision, Q&A, or next steps.
- Content slides should generally place the title across the top with the content below. Title, agenda, separator, summary, conclusion, and Q&A slides may use left-weighted or centered layouts.
- Content-slide titles should aim to fit on one line at a 1200px-wide viewport. Shorten the claim before shrinking type.
- Omit kickers/eyebrow labels by default. Add one only when it gives necessary orientation that the title cannot carry.

## Quality Bar

Every deck should be scan-ready, even if the audience is technical.

- Prefer less slide text and stronger hierarchy.
- Give each slide one dominant job.
- Use images, diagrams, charts, tables, code, icons, figures, and spatial composition when they explain faster than paragraphs.
- Use proven libraries, renderers, syntax highlighters, charting tools, and icon sets when they materially improve the slide. Do not hand-roll complex domain rendering when a stable tool can do it better.
- Avoid defaulting to three cards, repeated panels, or generic process arrows.
- Keep a consistent visual system inside one deck, but let different decks look genuinely different.
- Make section breaks feel like transitions, not content slides.
- Use appendix/detail slides for proof that would crowd the main story.
- If a slide feels crowded, split it or simplify it before shrinking type.
- Balance the slide body across the artboard. Avoid concentrating all meaningful content at the top, in one corner, or in one dense strip when the message should feel centered and composed.
- Unless the user provides a brand system, start from muted warm white backgrounds, black primary text, and restrained accent colors for highlights, status, and emphasis.
- Slides should look like real slides. Do not add explanatory copy about why a layout works.

## Visual QA Playbook

Before showing the user, render the deck in a browser and critique the screenshots yourself. Use Playwright when available; use the screenshot helper only as a fallback:

```sh
uv run --script ~/.claude/skills/skill-builder/tools/screenshot.py /tmp/<deck-slug>/<deck-slug>.html
```

Use a fixed slide artboard and scale it from the center. For Reveal decks, keep `width: 1280`, `height: 800`, `margin: 0`, and `center: false`; for custom galleries or single-slide review pages, wrap the 1280x800 slide in a centered scale-to-fit frame.

Check at least these Playwright viewports before calling a deck ready:

- `1440x900`
- `1280x800`
- `1200x800`
- `1024x768`
- `900x600`
- `768x1024`

For every review viewport, verify:

- clipped or overlapping text
- unwanted page scroll on normal desktop/tablet review sizes
- slide artboard centered in the viewport
- slide content centered inside the artboard when the layout calls for it
- long titles
- weak visual hierarchy
- content mass that is visually top-heavy, corner-heavy, or awkwardly uncentered
- dense blocks that are hard to scan
- repeated layouts that make the deck feel samey
- diagrams, charts, or images with unclear emphasis
- footer, metadata, or slide-count mistakes when the deck uses repeated chrome

When a screenshot fails, fix the layout first: shorten text, simplify the visual, split the slide, or adjust the artboard scaling. Do not solve crowded slides by making all text smaller.

Then show the user the deck and ask for critique. When feedback is broad, first propose a slide-level revision plan; when feedback is specific, implement and re-render.

## Output Contract

- Deliver one file named `<presentation-name>.html` unless the user asks for an asset folder.
- The file may link Reveal.js and optional libraries by CDN, but deck CSS should be inline.
- Default Reveal initialization: `width: 1280`, `height: 800`, `margin: 0`, `center: false`.
- The deck must be usable by opening the HTML directly in a browser.
- Repeated footers or metadata are optional. If used, keep deck-level labels stable and use slide content for section markers.

## References

- `examples/gallery/index.html` - fast visual scan of slide possibilities.
- `examples/design-gallery/index.html` - redirect kept for older references.
- `examples/` - complete fictional decks with different visual systems.
- `references/layouts.md` - compact guidance for choosing slide jobs without becoming template-bound.
- `references/variants.md` - register, chrome, and deck-level identity.
- `templates/theme.css` - foundation CSS to inline and adapt.
- `templates/deck.html.template` - single-file HTML skeleton.
