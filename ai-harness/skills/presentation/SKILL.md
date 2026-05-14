---
name: presentation
description: Build a shareable HTML slide deck when the user says "make a presentation", "build a deck", "make a pitch deck", "make slides", "explainer deck", "discussion deck", "townhall deck", or wants a self-contained HTML file they can present or send. Produces one polished browser-openable HTML file, usually with Reveal.js.
---

# presentation

Build one polished, browser-openable HTML slide deck. Treat this as a collaborative design session: align on intent, draft a complete V1, review screenshots, and iterate.

## Layout

```text
presentation/
├── SKILL.md
├── templates/
│   ├── deck.html.template
│   └── theme.css
├── references/
│   ├── layouts.md
│   ├── rubric.md
│   ├── taste.md
│   └── workflow.md
└── examples/
    ├── single-slide-examples/
    │   ├── gallery.html
    │   └── *.html
    └── full-slide-examples/
        └── *.html
```

## How to Use the Examples

- `examples/single-slide-examples/gallery.html` is for human review and fast visual scanning.
- The individual HTML files in `examples/single-slide-examples/` are inspiration for slide concepts, visual relationships, spacing, and hierarchy.
- `examples/full-slide-examples/` is reserved for complete end-to-end example decks as single HTML files.
- Do not treat the examples as templates, a taxonomy, or a component library. Open a relevant example to study why it works, then design the user's slide from the user's content.
- End-to-end example decks should be single HTML files under `examples/full-slide-examples/` unless assets are truly required.

## Alignment

A presentation is a compression of deep user context, not a formatting pass over a topic. Before drafting any outline or HTML, transfer enough context that the deck can reflect the user's real knowledge, judgment, and taste.

Ask concise questions first; use multiple-choice wording for real tradeoffs and free-form questions when the user needs to brain-dump. Use the question tool when available. Pull context from docs, notes, screenshots, data, existing decks, examples, and web research when the deck depends on facts outside the conversation.

Settle these before drafting:

- **Deep material:** facts, tensions, anecdotes, data points, examples, objections, decisions, constraints, and half-formed arguments.
- **Audience and room:** who is present, how senior, read-ahead vs. live voiceover, and what they already believe.
- **Purpose and thesis:** what the deck must accomplish, stated in the user's language, and the one sentence the audience should retain.
- **Narrative shape:** how the audience should move from current belief to intended action or understanding.
- **Length and slide/speaker split:** target slide count, appendix needs, what must be legible, and what the presenter will say.
- **Inputs and constraints:** required artifacts, brand requirements, banned wording, sensitive topics, shareability needs, and style preferences.
- **Visual stance:** density, proof depth, image use, chart use, technicality, formality, and what "good" means for this user.

**Threshold (high push):** Do not propose a slide-by-slide outline, produce HTML, or present a formal implementation plan as a substitute for alignment until you can state what deep material you have, what is still missing, and why the deck can now be responsibly compressed. Reflect that understanding back and ask: "Is there anything else I need to know, or should I build a V1 for us to critique?" Wait for explicit approval.

## Build Workflow

1. Follow `references/workflow.md`: transfer context, reflect sufficiency, get permission for a V1, draft, self-review, and iterate.
2. Pick a working directory under `/tmp/<deck-slug>/`.
3. Copy `templates/deck.html.template` to `/tmp/<deck-slug>/<deck-slug>.html`.
4. Inline `templates/theme.css` into the `<style>` slot, then adapt or replace it for the user's room.
5. Delete placeholder slide content before delivery.
6. Keep the final deliverable as one named HTML file unless the user explicitly wants a folder of assets.
7. Link optional libraries by CDN when they improve the result, such as Reveal.js, syntax highlighting, charts, math rendering, icon sets, or diagram tools.
8. Use `references/rubric.md`, `references/taste.md`, `references/layouts.md`, and relevant single-slide examples to review quality before showing the user.

## Deck Structure

Default to this deck arc unless the user's context clearly needs a different shape:

```text
title -> agenda -> separator for agenda item 1 -> content -> separator for agenda item 2 -> content -> ... -> final slide
```

- Keep agendas to 5 items or fewer.
- By default, each agenda item starts a section and gets its own separator slide before that section's content. If the deck uses an agenda, the audience should feel the same chunking in the slide flow.
- Use separators as transitions, not content slides. Include a short section label and, when helpful, a minimal subtitle there rather than repeating explanatory subtitles on content slides.
- Choose the final slide intentionally: summary, conclusion, decision, Q&A, or next steps.
- Content slides should generally place the title across the top with the content below.
- Title, agenda, separator, summary, conclusion, and Q&A slides may use centered or left-weighted layouts because they carry less body information.
- Content-slide titles should aim to fit on one line at a 1200px-wide viewport. Shorten the claim before shrinking type.
- Do not add a subtitle to a content slide by default. Add one only when the audience needs it to understand the slide's frame; otherwise let the title and visual do the work.
- Write high-emphasis text to render on one line inside its container: titles, section labels, KPI values, outcome statements, callout headers, and other bold scan targets should be concise enough to understand without a line break.
- Reserve multi-line wrapping for smaller supporting copy.
- Omit kickers/eyebrow labels by default. Add one only when it gives necessary orientation that the title cannot carry.

## Quality Bar

Every deck should be scan-ready, even if the audience is technical.

- Prefer less slide text and stronger hierarchy.
- Give each slide one dominant communicative purpose, written in the user's context rather than selected from a fixed list.
- Use images, diagrams, charts, tables, code, icons, figures, and spatial composition when they explain faster than paragraphs.
- Use proven libraries, renderers, syntax highlighters, charting tools, and icon sets when they materially improve the slide.
- Avoid defaulting to three cards, repeated panels, or generic process arrows.
- Do not over-copy structures from examples. Examples calibrate taste, spacing, hierarchy, and craft; they are not components to reuse until every deck looks the same.
- Keep a consistent visual system inside one deck, but let different decks look genuinely different.
- Make section breaks feel like transitions, not content slides.
- Use appendix/detail slides for proof that would crowd the main story.
- If a slide feels crowded, split it or simplify it before shrinking type.
- Balance the slide body across the artboard. Avoid concentrating all meaningful content at the top, in one corner, or in one dense strip.
- Unless the user provides a brand system, start from muted warm white backgrounds, black primary text, and restrained accent colors for highlights, status, and emphasis.
- Slides should look like real slides. Do not add explanatory copy about why a layout works.

## Visual QA Playbook

Before showing the user, render the deck in a browser and critique screenshots yourself. Prefer Playwright or another browser automation tool when available; otherwise use whatever screenshot workflow the environment provides. Save QA screenshots and traces under `/tmp/<deck-slug>/qa/` or another temporary location, not in the repository or current working directory.

Use a fixed slide artboard and scale it from the center. For Reveal decks, keep `width: 1280`, `height: 800`, `margin: 0`, and `center: false`; for custom single-slide review pages, wrap the 1280x800 slide in a centered scale-to-fit frame.

Check at least these viewports before calling a deck ready:

- `1440x900`
- `1280x800`
- `1024x768`
- `900x600`
- `768x1024`

For every review viewport, verify:

- clipped or overlapping text
- unwanted page scroll on normal desktop/tablet review sizes
- slide artboard centered in the viewport
- slide content centered inside the artboard when the layout calls for it
- long titles
- high-emphasis text wrapping onto multiple lines where the audience should skim it instantly
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
- Default Reveal initialization: `width: 1280`, `height: 800`, `margin: 0`, and `center: false`.
- The deck must be usable by opening the HTML directly in a browser.
- Repeated footers or metadata are optional. If used, keep deck-level labels stable and use slide content for section markers.

## References

- `examples/single-slide-examples/gallery.html` - human review page for the single-slide example set.
- `examples/single-slide-examples/*.html` - individual slide examples to inspect for inspiration.
- `examples/full-slide-examples/*.html` - complete example decks, added only after the skill succeeds in a real end-to-end run.
- `references/workflow.md` - collaborative staged workflow from discovery to final delivery.
- `references/rubric.md` - deck-level and slide-level review criteria.
- `references/taste.md` - visual taste rules and hierarchy guidance.
- `references/layouts.md` - guidance for designing visual relationships without becoming template-bound.
- `templates/theme.css` - sparse foundation CSS to inline and adapt.
- `templates/deck.html.template` - single-file HTML skeleton.
