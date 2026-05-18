# Alignment Patterns

**When to read this:** when deciding whether a new skill needs an `## Alignment` section, and — if so — how to phrase the threshold for proceeding.

The framework gives every skill an *optional* Alignment phase: a structured back-and-forth before producing the artifact. This file says when to include it, when to skip it, how hard to push for sign-off, and how to write the section without falling into common traps.

## When to include alignment

Add `## Alignment` when **any** of these is true:

- The output depends heavily on user intent that can't be inferred from the prompt or repo (presentations, tutorials, design docs, anything generative and long).
- The scope is genuinely ambiguous (a refactor that could touch 3 files or 30; a "clean up" with no clear stop point).
- The cost of a wrong direction is high — long generation, irreversible side effect, or work the user will throw out if mis-aimed.

## When to skip alignment

Skip the section entirely when **any** of these is true:

- The inputs fully specify the output (validators, formatters, schema checkers).
- The skill is a thin wrapper over a deterministic tool (lint, build, test runner).
- The user already provided everything needed in their prompt and asking again would feel insulting.

A skill with no Alignment section signals: *"hand me your inputs and I'll produce the artifact — no negotiation needed."* That's a feature, not a gap. Don't pad.

## Describing how hard the skill pushes for sign-off

The framework deliberately avoids a shared intensity vocabulary ("light/medium/aggressive") because those words mean different things to different agents. Instead, write the threshold in plain language: *what gets confirmed* and *when production starts*.

Three reference phrasings at different push intensities:

- **Low push** — *"Confirm whether the target is the uncommitted diff or a specific PR; one short turn, then proceed."*
- **Medium push** — *"Propose the refactor approach in two sentences and wait for a thumbs-up before editing files."*
- **High push** — *"Do not produce any HTML until the user has explicitly approved a written slide-by-slide outline."*

The third is what other frameworks would call "aggressive." Writing it out leaves no ambiguity about the threshold — much better than a label like `priority: high`.

## Anti-patterns

Don't ship an Alignment section that does any of these:

- **Asks trivia the model can read.** File paths, function names, the contents of `package.json`. Read the repo first, ask second.
- **Asks before reading what the user already gave.** If the user wrote *"audit `src/auth/`"*, don't ask "which folder?".
- **Buries the user in 10 questions at once.** Converge in 2–3 turns. If you need more, the skill's scope is too broad.
- **Asks alignment questions and then ignores the answers.** Echo the user's choices back into the artifact (an outline they approved, a tone they specified). If the answers don't change the output, don't ask.

## Worked example — low push

Skill: `commit-message-from-diff`. Reads the staged diff, drafts a commit message in the project's format.

> **Alignment**
>
> Before executing, settle the following with the user:
>
> - Whether the staged diff is the right scope (vs. a specific subset of files).
>
> Confirm one ambiguous point and proceed. If the staged diff looks scoped to a single change, skip the question and produce the message directly.

One dimension. One question. Pre-emptive escape hatch when no question is needed. The user types one word back ("yes") and the skill commits.

## Worked example — high push

Skill: `presentation`. Produces a 10–20 slide self-contained HTML deck for a user-defined topic.

> **Alignment**
>
> Before executing, settle the following with the user:
>
> - **Audience** — who's in the room (technical depth, prior knowledge, role).
> - **Outcome** — what should the audience think, feel, or do after the deck.
> - **Slide-by-slide outline** — a written list of slide titles + one-sentence intent each.
> - **Must-haves and must-avoids** — required points, sensitive topics, deal-breakers.
>
> Do not produce any HTML until the user has explicitly approved the written outline. Iterate on the outline freely; it's cheap. The deck is expensive — produce it once, after sign-off.

Four dimensions, but they form a clear sequence (audience → outcome → outline → guardrails). The threshold sentence is unambiguous: HTML waits until the outline is signed off in text. The user always knows what state the skill is in.

## Calibration loop — aligning via sample artifacts

For skills whose output quality is hard to specify in prose — anything generative, anything aesthetic, anything where "good" is ineffable — sample artifacts are the medium of alignment. Outlines and written specs are too abstract; only a concrete artifact reveals what the user actually wants.

The pattern: produce 1–3 sample artifacts on hypothetical inputs *as if the skill were already built*; iterate on user feedback; bake the preferences extracted from approved samples into the skill itself. The samples are throwaway; the calibration is what survives. The approved samples then graduate into the new skill's `examples/` folder as the strongest possible documentation of the quality bar.

This applies to both visual and non-visual artifacts. Skill-builder uses this loop in Phase 2 of its `## How to Run` whenever it scaffolds a new skill.

### Worked example — visual: building `/fitness-report`

**Phase 1 (Discover):** intensive Q&A. Skill-builder learns: name `/fitness-report`, archetype = visual artifact, install location, generic across users (not project-specific), audience = the user themselves, success = "I want to scan it in 10 seconds and see whether last week was good," failure = "boring spreadsheet vibes," constraints = "uses my design system," iteration model = input-driven (no per-run alignment).

**Phase 2 (Calibrate):** skill-builder scaffolds a draft at `/tmp/fitness-report-sample/index.html` using the design-system tokens with mock fitness data. Renders the activity heatmap as a gray sequential ramp (per the chrome rules, naively applied). User reacts: *"the gray heatmap looks weirdly muted and confusing."* Skill-builder reads `design-system/preferences.md` § *Content palette*, redrafts with the green sequential ramp, re-renders. User: *"yes, exactly."* That's the approval signal.

**Phase 3 (Extract):** preferences from the approved sample — heatmap = green sequential ramp; donut = blue sequential ramp; period toggle = yellow active state; metric cards stack with sparklines; Chart.js for the line chart. These get baked into `templates/styles.css` and `templates/index.html.template` in the new skill.

**Phase 4 (Scaffold):** create `~/generic/dotfiles/ai-harness/skills/fitness-report/` with `SKILL.md`, `templates/`, and `examples/` containing the approved Phase-2 sample as `examples/sample-week.html`.

**Phase 5 (Verify):** `tools/verify.sh` passes.

### Worked example — non-visual: building `/commit-from-diff`

**Phase 1 (Discover):** intensive Q&A. Skill-builder learns: name `/commit-from-diff`, archetype = structured text, install location, scope = staged diff (not arbitrary commit ranges), audience = git history (the user re-reads commits months later), success = "the body explains *why* not *what* — I can read the diff for *what*," failure = "conventional-commits prefixes (we don't use them) or one-line subjects with no body for non-trivial changes," reference = "Linus's good ones," constraints = "subject ≤ 50 chars," iteration model = each invocation needs negotiation (the new skill itself will have an `## Alignment` section to confirm scope).

**Phase 2 (Calibrate):** skill-builder mocks up a hypothetical staged diff (a small refactor extracting a helper function) and produces 3 draft commit messages — one terse, one verbose, one conventional-commits style. User reacts: *"more terse than the verbose one but lead with the why like that one did. drop the conventional-commits prefix — we don't use them."* Skill-builder produces a single redrafted message. User: *"yes."* Approval.

**Phase 3 (Extract):** preferences — subject ≤ 50 chars, imperative mood; body 1–2 sentences explaining why, not what; no conventional-commits prefix; trailers include `Co-Authored-By: Claude`. These become the content of `references/format.md` plus three good/bad pairs in `examples/`.

**Phase 4 (Scaffold):** create `~/generic/dotfiles/ai-harness/skills/commit-from-diff/` with `SKILL.md`, `references/format.md`, and `examples/` containing both the approved sample message and the good/bad pairs.

**Phase 5 (Verify):** `tools/verify.sh` passes.

### When the calibration loop is overkill

Skip the sample-iteration loop when:

- The skill is a thin wrapper over a deterministic tool (`run-tests`, `format-code`).
- The output format is fully specified by an external standard (a JSON Schema, a protocol message, an RFC).
- The user has provided exhaustively detailed specifications — and you've sanity-checked they actually have.

For these, fall back to the lighter Discover → Scaffold → Verify path. Sample iteration is a *cost*; spend it where the user genuinely can't pre-specify "good."

## Promoting from sample → reusable asset

Phase 3 step 2 (extract assets) and step 3 (propose design-system backflow) are abstract until you've seen one case. Here's how it plays out for a hypothetical `/quality-audit` skill, drawn from the actual `design-system/examples/code-quality-report/` artifact in this repo.

During Phase 2 iteration, two things crystallized that weren't in the design system or in any other skill:

1. A **unified-diff renderer in JS** — `renderUnifiedDiff(before, after)` using `Diff.diffLines` + `Diff.diffWordsWithSpace` to produce GitHub-style line-and-word diff markup. Used across every "before/after" finding in the sample.
2. A **translucent rgba word-diff overlay pattern** — `rgba(220,38,38,0.20)` on red lines and `rgba(22,163,74,0.22)` on green reads cleaner than solid background swatches.

**Phase 3 step 2** (within-skill): the diff renderer is a real reusable asset — many findings use it, and a future invocation would want to call into it rather than re-derive. It graduates from inline `examples/code-quality-report/script.js` into `<skill>/templates/diff-renderer.js`. The new skill's SKILL.md instructs the agent to "render diffs using `templates/diff-renderer.js`." The sample stays in `examples/` verbatim — that's the artifact the user approved.

**Phase 3 step 3** (design-system backflow): the translucent rgba overlay isn't specific to code review — anywhere two color-coded states overlay text, the same restraint reads better. That's a candidate for `design-system/preferences.md` § Content palette: a one-line note about preferring translucent overlays over solid swatches when text remains primary. Surface this to the user; if they say yes, propose the prose diff against `preferences.md` separately. If no, the skill keeps the pattern internal.

Both flows in one case: the renderer is *skill-internal reusable*, the overlay convention is *design-system-wide reusable*. They're decided independently.

## Closing rule

If you're unsure whether to include alignment, ask: *"will the user be able to tell, from the artifact alone, whether this matched their intent?"* If yes, skip alignment. If no, you need it — and the section should converge on whatever dimension makes the answer "yes."
