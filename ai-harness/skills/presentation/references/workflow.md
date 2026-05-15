# Presentation Workflow

This is a collaborative working-session workflow. Do not draft slides before the deck is scoped well enough for critique.

## 1. Discover

Treat discovery as context transfer. A deck compresses the user's knowledge, so shallow metadata is not enough. Audience, length, and tone guide the work; they do not replace the raw material the deck must compress.

Gather enough substance to understand:

- the user's actual goal and why the presentation needs to exist
- facts, examples, anecdotes, data points, tensions, objections, and decisions
- docs, notes, screenshots, existing decks, datasets, or links the agent should inspect
- what the audience already believes and what must change
- the working thesis and likely narrative order
- what belongs on slides vs. what the presenter will say
- visual stance, constraints, banned moves, and what "good" means for this user

Use concise multiple-choice questions for real tradeoffs. Use free-form questions when the user needs to brain-dump context. Research or inspect artifacts when needed; do not make the user answer questions the environment can answer. Do not ask the user to design the deck for you.

Never treat a few routing answers as sufficient context. If the substantive material is thin, keep interviewing or ask for artifacts before outlining.

## 2. Reflect Back

Before outlining or drafting, restate the understanding in plain language:

- who the deck is for
- what it must accomplish
- the deep material the agent has absorbed
- the important gaps or assumptions that remain
- why the material is now sufficient to compress into a deck
- the likely narrative arc
- what belongs on slides vs. in voiceover
- the visual direction
- known risks, constraints, or banned moves

End this stage with: "Is there anything else I need to know, or should I outline the deck for review?"

Do not substitute a slide outline, implementation plan, or confident thesis statement for this checkpoint. Wait for explicit approval before outlining the deck.

## 3. Outline the Deck

After the user explicitly approves the reflected understanding, present the complete planned deck before building HTML. The outline is the user's chance to reshape the narrative while changes are still cheap.

Include every slide in order. For each slide, state:

- draft title
- context or job of the slide
- desired audience takeaway
- planned visual, chart, diagram, image, table, code, or spatial composition

Keep it readable. Group slides by section, use compact bullets or a table, and keep each slide entry short enough to scan. Do not write full speaker notes or long slide copy unless the user specifically asks for that detail.

End by asking what should change, or whether to build the V1 from the outline. Wait for explicit approval before drafting HTML.

## 4. Build V1

After the user explicitly approves the deck outline, build a complete reviewable V1. A V1 should be concrete enough to critique visually and narratively.

Default arc:

```text
title -> agenda -> separator for agenda item 1 -> content -> separator for agenda item 2 -> content -> final slide
```

When a deck includes an agenda, keep the agenda slide subtitle-free by default. Each agenda item should usually become a visible section with its own separator slide, followed by at least two content slides. Adapt the arc when the user's context demands it, but do not let the agenda promise structure that the slide flow does not deliver.

If a section has only one content slide, treat that as a sign the agenda is probably too granular. Merge thin sections before drafting unless the user explicitly wants a very short or unusual deck.

Content-slide subtitles are optional. Use them when they supply necessary frame or evidence context; otherwise remove them and let the title, visual hierarchy, and section separator carry orientation.

## 5. Self-Review

Before showing the user, run the rubric and visual QA passes:

- deck-level argument pass
- slide-level job and scan pass
- text density pass
- high-emphasis one-line pass
- content mass and balance pass
- viewport and screenshot pass

Fix issues before asking the user to review.

## 6. Critique and Iterate

Ask for targeted critique after V1. When feedback is broad, propose a slide-level revision plan. When feedback is specific, implement it and re-render.

Treat the single-slide examples as calibration. They should influence quality, hierarchy, and range, not become components to copy.

## 7. Finalize

Before final delivery:

- remove placeholder language and process commentary
- verify links, assets, fonts, and optional CDNs
- render screenshots at required viewports
- confirm no unwanted scrolling or clipping
- ensure the final HTML opens directly in a browser
