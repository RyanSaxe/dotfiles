# Layout and Visual Relationships

This reference is a compass, not a component API. Do not choose a slide from a menu. Start with what the audience must understand, then design the visual relationship that makes that understanding fast.

Open `examples/single-slide-examples/gallery.html` for a quick scan of the example set. Open individual files when a specific slide raises a useful question about spacing, hierarchy, density, or visual representation.

## Design From the Relationship

Ask what relationship the slide needs to make visible:

- what changed
- what matters most
- what depends on what
- what moved from current state to target state
- what is on track, at risk, or blocked
- what tradeoff the room must decide
- what evidence supports the claim
- what part of a larger system deserves focus

This list is not a taxonomy. It is a way to avoid designing from generic containers. If the relationship is unclear, keep interviewing or rewrite the slide's claim before choosing a layout.

## Working Principles

- Start with the slide's claim and the audience's next thought.
- Pick the visual form that makes that claim fastest to understand.
- Use fewer words than feels comfortable on the first pass, then add only what the audience truly needs on the slide.
- Use cards only when they express a real grouping, comparison, state, or peer set.
- Keep one deck visually coherent through type scale, color meaning, spacing, and chrome.
- Let different decks have different visual systems when the room, content, or brand calls for it.

## Template CSS

`templates/theme.css` is deliberately sparse. It establishes the fixed artboard, typography, background, and a few layout primitives. It is not a component library and should not decide the deck's visual system.
