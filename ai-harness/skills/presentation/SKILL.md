---
name: presentation
description: Build, polish, edit, or visually improve a shareable HTML slide deck when the user says "make a presentation", "build a deck", "make a pitch deck", "make slides", "edit this deck", "polish these slides", "improve this presentation", "explainer deck", "discussion deck", "townhall deck", or wants a self-contained HTML file they can present or send. Produces one polished browser-openable HTML file, usually with Reveal.js.
---

# presentation

Build one polished, browser-openable HTML slide deck. Treat this as a collaborative design session: align on intent, draft a complete V1, review screenshots, and iterate.

## Layout

```text
presentation/
├── SKILL.md
├── tools/
│   └── deck_qa.py
├── templates/
│   └── deck.html.template
├── references/
│   ├── layouts.md
│   ├── planning-example.md
│   ├── rubric.md
│   ├── taste.md
│   ├── visuals.md
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
- Do not treat example content, diagrams, or visual subjects as templates, a taxonomy, or a component library. Open relevant examples to study why they work, then design the user's slide from the user's content.
- End-to-end example decks should be single HTML files under `examples/full-slide-examples/` unless assets are truly required.
- Before coding a V1, inspect at least one full example deck when available and either the single-slide gallery or 3-5 relevant single-slide examples. Use them to calibrate density, hierarchy, visual range, slide text density, and pre-read balance. The example content and one-off diagrams are inspiration only.

## Default Deck System

The default deck system is not example inspiration. It is the starting structure and look-and-feel for decks made with this skill unless the user asks for a different system or there is a strong reason to ask for approval to deviate.

- Use the self-contained `templates/deck.html.template` as the canonical starter. It includes the base CSS, Reveal.js setup, required chrome, and commented optional chart CDN.
- Keep the deck full-screen in Reveal.js with native navigation arrows, progress bar, bottom-left slide numbers, fixed 1280x800 artboard, `margin: 0`, and `center: false`.
- Keep title, agenda, section separator, and final slides in the established left/right composition by default.
- Keep content slides in the established top-title composition by default, with the slide body below.
- Keep the agenda slide as the specific stable orientation slide: left title, right numbered agenda path, no subtitle by default.
- Preserve the default voice: concise executive claims, low slide-text density, direct labels, and nuance left for speaker notes unless the room needs it on-slide.
- Content-slide visuals have broad freedom. Design charts, diagrams, screenshots, tables, code, images, or spatial compositions around the user's actual message rather than choosing from example slides.
- Change the deck system only when the user explicitly asks, a supplied brand or prior deck requires it, or the content cannot be explained well inside the system. If the reason is not obvious from the user's request, ask before changing it.

## Alignment

A presentation is a compression of deep user context, not a formatting pass over a topic. Before drafting any deck outline or HTML, transfer enough context that the deck can reflect the user's real knowledge, judgment, and taste.

Ask concise questions first; use multiple-choice wording for real tradeoffs and free-form questions when the user needs to brain-dump. Use the question tool when available. Pull context from docs, notes, screenshots, data, existing decks, examples, and web research when the deck depends on facts outside the conversation.

Settle these before drafting:

- **Deep material:** facts, tensions, anecdotes, data points, examples, objections, decisions, constraints, and half-formed arguments.
- **Audience and room:** who is present, how senior, read-ahead vs. live presentation, and what they already believe.
- **Purpose and thesis:** what the deck must accomplish, stated in the user's language, and the one sentence the audience should retain.
- **Narrative shape:** how the audience should move from current belief to intended action or understanding.
- **Length and presenter context:** target slide count, appendix needs, what must be legible, and what the presenter can explain instead of putting on slides.
- **Inputs and constraints:** required artifacts, brand requirements, banned wording, sensitive topics, shareability needs, and style preferences.
- **Visual stance:** density, proof depth, image use, chart use, technicality, formality, and what "good" means for this user.

**Threshold (high push):** Do not propose a slide-by-slide outline, produce HTML, or present a formal implementation plan as a substitute for alignment until you can state what deep material you have, what is still missing, and why the deck can now be responsibly compressed. Reflect that understanding back and ask: "Is there anything else I need to know, or should I outline the deck for review?" Wait for explicit approval before outlining.

## Outline Checkpoint

After the user approves the reflected understanding, outline the whole deck before building the V1. Make the outline concrete enough for clean feedback without becoming a dense script.

Start the outline with a count and structure contract:

- target number of visible slides
- whether the count includes title, agenda, separators, content slides, appendix, and final slide; default to including every visible slide unless the user says otherwise
- agenda sections and the content-slide range under each section
- planned separator slide for each agenda section, including the separator's visual concept
- pacing notes for sections with fewer than two or more than three content slides

Include every planned slide in order. For each slide, use this human-readable structure:

- draft title
- **Role:** why this slide exists in the story
- **Message:** what the audience should understand
- **Visual:** the planned visual relationship, chart, diagram, image, table, code, or spatial composition
- **Notes:** optional constraints, density guidance, or important context that should not become slide prose

Keep the outline readable in a terminal: use clear section separators, then one compact slide block at a time with indented labeled lines. Do not use Markdown tables. Avoid decorative blank spacer lines inside repeated slide entries; blank lines should separate major sections or slide blocks, not every field. Keep each slide entry to the minimum needed for the user to critique the sequence, message, visuals, and pacing. Do not write long narration or detailed slide wording at this stage.

End by asking what should change, or whether to build the V1 from the outline. Wait for explicit approval before drafting HTML.

## Build Workflow

1. Follow `references/workflow.md`: transfer context, reflect sufficiency, get permission to outline, outline the deck, get permission for a V1, draft, self-review, and iterate.
2. Before coding V1, run the example calibration pass described above. Use examples to calibrate craft, not to select slide types or reuse example content.
3. Pick a working directory under `/tmp/<deck-slug>/`.
4. Copy `templates/deck.html.template` to `/tmp/<deck-slug>/<deck-slug>.html`.
5. Start from the inline CSS and script already in the HTML template. Preserve the default deck system unless the user has approved a different system.
6. Delete placeholder slide content before delivery.
7. Keep the final deliverable as one named HTML file unless the user explicitly wants a folder of assets.
8. Link optional libraries by CDN when they improve the result, such as syntax highlighting, charts, math rendering, icon sets, or diagram tools. Reveal.js is already in the template.
9. Use `references/rubric.md`, `references/taste.md`, `references/layouts.md`, `references/visuals.md`, and relevant examples to review quality before showing the user.

## Deck Structure

Default to this deck arc unless the user's context clearly needs a different shape:

```text
title -> agenda -> separator for agenda item 1 -> content -> separator for agenda item 2 -> content -> ... -> final slide
```

- Keep agendas to 5 items or fewer.
- Agenda slides should not have subtitles by default. Let the agenda be a stable, low-friction orientation slide: title plus section names.
- By default, each agenda item starts a section and gets its own separator slide before that section's content. If the deck uses an agenda, the audience should feel the same chunking in the slide flow.
- Agenda items should be real chunks, not labels for one-slide sections. During alignment, choose agenda items that can each support at least two content slides; if a section is too thin, merge it before drafting.
- Use separators as transitions, not content slides. Include a short section label and, when helpful, a minimal subtitle there rather than repeating explanatory subtitles on content slides.
- Choose the final slide intentionally: summary, conclusion, decision, Q&A, or next steps.
- Content slides should place the title across the top with the content below unless the user has approved a different deck system.
- Title, agenda, separator, and final slides should use the default left/right compositions in the HTML template unless the user has approved a different deck system.
- Content-slide titles should aim to fit on one line at a 1200px-wide viewport. Shorten the claim before shrinking type.
- Do not add a subtitle to a content slide by default. Add one only when the audience needs it to understand the slide's frame; otherwise let the title and visual do the work.
- Write high-emphasis text to render on one line inside its container: titles, section labels, KPI values, outcome statements, callout headers, and other bold scan targets should be concise enough to understand without a line break.
- Reserve multi-line wrapping for smaller supporting copy.
- Omit kickers/eyebrow labels by default. Add one only when it gives necessary orientation that the title cannot carry.

## Quality Bar

Every deck should be scan-ready, even if the audience is technical.

- Prefer purposeful slide text and stronger hierarchy: slides should be skimmable as pre-read material without becoming self-narrating. Use short claims, labels, evidence anchors, and necessary context; keep nuance and caveats out of slide prose unless the room requires them.
- Give each slide one dominant communicative purpose, written in the user's context rather than selected from a fixed list.
- Use images, diagrams, charts, tables, code, icons, figures, and spatial composition when they explain faster than paragraphs.
- For standard quantitative charts in HTML decks, prefer Chart.js by CDN over hand-rolled SVG/CSS/canvas chart geometry. Use D3, Observable Plot, or custom code only when the chart needs a relationship Chart.js cannot express cleanly.
- Use proven libraries, renderers, syntax highlighters, charting tools, and icon sets when they materially improve the slide.
- Avoid defaulting to three cards, repeated panels, or generic process arrows.
- Do not over-copy example content or one-off diagrams. Examples calibrate taste, spacing, hierarchy, and craft; the default deck system supplies the shared skeleton.
- Keep a consistent visual system inside one deck, but let different decks look genuinely different.
- Make section breaks feel like transitions, not content slides.
- Use appendix/detail slides for proof that would crowd the main story.
- If a slide feels crowded, split it or simplify it before shrinking type.
- Balance the slide body across the artboard. Meaningful content should usually feel centered both horizontally and vertically within its intended region; avoid concentrating it at the top, bottom, in one corner, or in one dense strip unless the imbalance is deliberate and useful.
- Unless the user provides a brand system, start from muted warm white backgrounds, black primary text, and restrained accent colors for highlights, status, and emphasis.
- Slides should look like real slides. Do not add explanatory copy about why a layout works.

## Visual QA Playbook

Before showing the user, render the deck with the presentation QA tool and critique screenshots yourself. Save QA screenshots and traces under `/tmp`, not in the repository or current working directory.

Use `tools/deck_qa.py` from this skill:

```zsh
uv run --script ai-harness/skills/presentation/tools/deck_qa.py /tmp/<deck-slug>/<deck-slug>.html --all
```

During iteration, capture only the slide or range being edited:

```zsh
uv run --script ai-harness/skills/presentation/tools/deck_qa.py /tmp/<deck-slug>/<deck-slug>.html --slide 7
uv run --script ai-harness/skills/presentation/tools/deck_qa.py /tmp/<deck-slug>/<deck-slug>.html --slides 3,4,8-10
```

The tool writes each run to a unique `/tmp/presentation-qa/...` directory by default, so concurrent QA runs do not overwrite each other. Use `--out /tmp/<deck-slug>/qa/<run-name>` only when a stable path is useful. Use `--fail-on-scroll` and `--fail-on-console-error` when checking a deck before delivery.

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
- content groups centered horizontally and vertically within their intended slide region unless the composition intentionally breaks that balance
- long titles
- high-emphasis text wrapping onto multiple lines where the audience should skim it instantly
- weak visual hierarchy
- content mass that is visually top-heavy, corner-heavy, or awkwardly uncentered
- dense blocks that are hard to scan
- repeated layouts that make the deck feel samey
- default deck system fit: title, agenda, separator, final, content-frame, Reveal controls, progress bar, bottom-left slide numbers, and full-screen behavior
- visual story/message fit: whether the visual relationship actually expresses the slide's claim
- diagrams, charts, or images with unclear emphasis
- footer, metadata, or slide-count mistakes when the deck uses repeated chrome

When a screenshot fails, fix the layout first: shorten text, simplify the visual, split the slide, or adjust the artboard scaling. Do not solve crowded slides by making all text smaller.

If browser preview tools or page annotations point at screenshots or temporary review HTML, treat that feedback as feedback on the real deck source. Apply the edit to the HTML file being authored, then rerun `deck_qa.py`; do not hand-edit generated temporary QA artifacts.

Then show the user the deck and ask for critique. When feedback is broad, first propose a slide-level revision plan; when feedback is specific, implement and re-render.

## Output Contract

- Deliver one file named `<presentation-name>.html` unless the user asks for an asset folder.
- Use real Reveal.js by default. Do not replace it with a custom slide framework unless the user explicitly requests no external dependencies or a non-Reveal runtime.
- The file may link Reveal.js and optional libraries by CDN, but deck CSS should be inline.
- Default Reveal initialization: `width: 1280`, `height: 800`, `margin: 0`, `center: false`, `slideNumber: "c/t"`, and `showSlideNumber: "all"`.
- The deck must be usable by opening the HTML directly in a browser.
- Repeated footers or metadata are optional. If used, keep deck-level labels stable and use slide content for section markers.

## References

- `examples/single-slide-examples/gallery.html` - human review page for the single-slide example set.
- `examples/single-slide-examples/*.html` - individual slide examples to inspect for inspiration.
- `examples/full-slide-examples/*.html` - complete example decks, added only after the skill succeeds in a real end-to-end run.
- `tools/deck_qa.py` - presentation-specific screenshot QA for full decks, selected slides, and single-slide HTML examples.
- `references/workflow.md` - collaborative staged workflow from discovery to final delivery.
- `references/planning-example.md` - reverse plan for the full `software-for-agents.html` example deck.
- `references/rubric.md` - deck-level and slide-level review criteria.
- `references/taste.md` - visual taste rules and hierarchy guidance.
- `references/layouts.md` - guidance for designing visual relationships without becoming template-bound.
- `references/visuals.md` - meaning-first visual guidance and anti-patterns.
- `templates/deck.html.template` - canonical single-file HTML starter with inline CSS, Reveal.js setup, and default deck system.
