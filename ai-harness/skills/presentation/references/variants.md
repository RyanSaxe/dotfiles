# Register, Footer, and Section Markers

The deck's register and footer language are things to figure out with the user. They are not selected from a fixed menu, and they are not inferred from a filename alone. Use the user's audience, stakes, timing, and intent to decide how the deck should speak and how the artifact should identify itself.

## Register

Before drafting, be able to state a working theory in plain language:

- who the deck is for
- what the room is supposed to do with it
- whether slides are read-ahead, live voiceover, or both
- how direct, formal, dense, visual, or conversational the deck should feel
- what material belongs in the main story vs. backup

The point is not to pick a label like "pitch," "explainer," or "executive." The point is to decide, for this specific room, what the audience needs to understand quickly and how much evidence, friction, softness, or directness the slides should carry.

The register should show up in concrete choices: title length, slide density, diagram style, amount of proof, section dividers, appendix separation, and how assertive the recommendation feels.

## Stable Footer Label

The footer label is deck-level metadata shared across slides. It should describe the whole artifact in the user's language, not the current section, topic, or slide type.

Work out the footer label from context:

- If the user calls it a board readout, use `Board readout`.
- If the user calls it a weekly product update, use `Product update`.
- If the room is a leadership discussion, use the phrase they would naturally use for that meeting.

Do not rotate the footer label by section. In a normal deck, the footer label should stay the same on the title slide, main-story slides, divider slides, and appendix slides.

`Appendix` is not a footer label for a deck with an appendix. Use `Appendix` as a section kicker, divider title, or slide marker. Only use `Appendix` in the footer if the entire file is a standalone appendix document.

## Kicker Labels

Kickers orient the audience within the story. Unlike the footer label, they may change slide to slide:

- context-setting labels
- problem or tension labels
- recommendation labels
- example labels
- risk or guardrail labels
- appendix labels

Keep kickers short. Avoid making them slide counters or verbose subtitles.

## Visual Register

Keep a consistent visual system inside one deck:

- One accent color should indicate the active recommendation or current focus.
- Semantic colors should have meaning and be used sparingly.
- A divider slide should be visibly quieter than content slides.
- Appendix slides can be more concrete, but must remain visually separate from the main story.

## Body Classes

`theme.css` may include body classes for broad visual treatment, but do not let body classes drive the narrative. Most decks can use the base styles and still feel tailored through wording, slide order, and layout choices.
