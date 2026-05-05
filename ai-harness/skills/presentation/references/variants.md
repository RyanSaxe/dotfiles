# Deck variants

Each deck opts into one variant via `<body class="deck-<variant>">`. Variants share all design tokens but differ in *character*: kicker style, type scale, accent application, title-slide composition. The point is distinct decks that still feel like the same family.

## When to pick which

| Variant | Use when… | Character |
| --- | --- | --- |
| **`deck-pitch`** | Persuading a decision-maker. Internal pitch, exec readout, ask for headcount/budget, RFC vote. | Yellow accent-pill kickers (`PROBLEM`, `ASK`, `DECISION`). Bigger type. Title slide is a TED-style centered headline. Includes pull-quote "moment" slides between content slides for rhetorical beats. Light on charts; heavy on rhetoric. |
| **`deck-explainer`** | Teaching a concept. Onboarding doc, technical explainer, "how X works" walkthrough, methodology overview. | Italic blue kickers with section markers (`§ 1 · Motivation`). Lighter heading weights. Title slide is paper-style with an italic abstract block. Heavy on diagrams, math, comparisons. Reads as longform — slides feel like sections of an article. |

A `deck-tech` variant exists in `theme.css` as a starting point but has no validated example yet — treat as experimental. For an engineering-internal tech talk, calibrate via the *Coining a new variant* recipe below before relying on it.

## How a variant differs in practice

Look at the two example decks side by side: same tokens, same chrome, same primitives — different feel.

- `examples/pitch-adopt-skills/` — opens with a yellow accent pill above a 112px headline. Slide 4 is a single pull-quote ("If it's not in a repo, it's not infrastructure"). Kickers are one-word labels (`PROBLEM`, `COST`, `ASK`).
- `examples/explainer-prompt-caching/` — opens with an italic abstract block top-and-bottom-bordered. Kickers are sectioned (`§ 1 · Motivation`, `§ 2 · Mental model`). Recap slide uses lowercase roman numerals (`i.`, `ii.`, `iii.`) on accent cards.

The variant doesn't dictate the slide *count* or the *structure* — those come from the conversation. It dictates the visual register the deck speaks in.

## Coining a new variant

If the user describes a use case where neither pitch nor explainer fits — say, a *status report* deck, or a *retro* deck, or a *workshop* deck — coin a new variant rather than forcing one of the existing ones.

The recipe:

1. Identify what's structurally different about the use case. (A status report wants more numbers and dates; a retro wants more 2-column "what worked / what didn't" layouts.)
2. Add a new section to `templates/theme.css` under "Deck variants" — only override the things that differ from base. Keep tokens shared.
3. Show the user one sample with the new variant. Iterate until they sign off.
4. If the variant feels stable enough that future invocations should know about it, document it in this file.

Failure mode: a variant that overrides so much it amounts to a different design system. If you find yourself overriding tokens (colors, fonts, spacing scale), stop — the requirement isn't a variant, it's a separate skill or a deliberate design-system extension. (The cross-skill version of this rule lives in the design-system preferences doc maintained by `skill-builder`.)
