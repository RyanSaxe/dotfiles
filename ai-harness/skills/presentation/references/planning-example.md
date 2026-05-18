# Planning Example: Software for Agents

This is a reverse plan for `examples/full-slide-examples/software-for-agents.html`.
Use it as a model for a human-readable deck outline before building a full deck.

Do not copy this deck's layout system by default. Copy the planning discipline:
count every visible slide, map agenda sections to separator slides, name the
visual job of each separator, and keep each slide block focused on story,
message, and visual direction.

## Example Calibration

- Density: most slides use one claim, one dominant visual relationship, and a few labels or short lines.
- Hierarchy: titles and visuals carry the argument; supporting text is brief and role-specific.
- Variety: the deck uses folders, quadrants, terminals, gates, template sheets, example cards, screenshot windows, and deck stacks.
- Pre-read balance: the deck is skimmable, but it does not try to narrate every caveat on the slide.
- Constraint: examples calibrate taste and judgment; they are not a component library.

## Count Contract

```text
Target: 16 visible slides
Includes: title, agenda, section separators, content slides, and final Q&A
Appendix: none
Agenda sections: 3
Separator rule: one separator slide per agenda section
Default pacing: each agenda section should carry at least two content slides
Pacing exception: section 3 has five content slides because it is the case-study proof sequence
```

Visible count:

- 01 title
- 02 agenda
- 03 section separator: Prompt Ceiling
- 04-05 Prompt Ceiling content
- 06 section separator: Capability Package
- 07-09 Capability Package content
- 10 section separator: Proof in Practice
- 11-15 Proof in Practice content
- 16 final Q&A

## Agenda Map

```text
1. Prompt Ceiling
   Separator: slide 03
   Separator visual: prompt sheet physically hitting a ceiling line
   Content slides: 04-05
   Section job: show why reusable prompting patterns still leave a missing layer

2. Capability Package
   Separator: slide 06
   Separator visual: exploded skill package with SKILL.md, references, tools, and examples
   Content slides: 07-09
   Section job: define a skill as packaged capability, not just prompting

3. Proof in Practice
   Separator: slide 10
   Separator visual: one polished slide-deck stack, distinct from the final artifact stacks
   Content slides: 11-15
   Section job: prove the presentation skill works as an incomplete software skeleton that agents complete downstream
```

## Slide Plan

```text
OPENING
01 Title: Software for Agents
   Role: establish the thesis and make the deck feel CEO-ready
   Message: skills package capability, not just instructions
   Visual: light-blue folder equipping an agent terminal
   Notes: one thesis sentence is enough; keep terminal and folder labels short

02 Agenda
   Role: orient the room without adding explanation
   Message: the story has three chunks
   Visual: centered agenda line with exact dot alignment
   Notes: no subtitle; this slide is the stable structure people can copy

SECTION 1: PROMPT CEILING
03 Separator: Prompt Ceiling
   Role: mark the first section and set up the limitation
   Message: text-only steering has a ceiling
   Visual: prompt page pressing into a ceiling line
   Notes: section title plus one short subtitle; separator visuals should feel distinct

04 Reusable prompts are not enough
   Role: show the main reusable prompt options and their gaps
   Message: templates, few-shot prompts, and sub-agents help, but remain incomplete
   Visual: prompt template card branching into few-shot and sub-agent cards
   Notes: label-led slide; do not turn the gap explanations into paragraphs

05 The missing layer is packaged capability
   Role: locate skills relative to reusable prompting patterns
   Message: skills occupy the missing space of context-rich packaged capability
   Visual: context vs. automation quadrant with the skill point emphasized
   Notes: keep terms short; explain sub-agents, custom agents, and skills only as needed

SECTION 2: CAPABILITY PACKAGE
06 Separator: Capability Package
   Role: transition from missing layer to anatomy
   Message: skills carry multiple capability surfaces together
   Visual: layered artifact cards for SKILL.md, references, tools, and examples
   Notes: artifact labels do the work; avoid explaining the whole folder structure here

07 A skill is a capability package
   Role: make the package shape concrete
   Message: the folder can ship behavior, materials, optional software, and assurance
   Visual: folder manifest next to meaning lanes
   Notes: clarify that not every skill needs every folder

08 Tools can ship with the skill
   Role: answer the "why not MCP" question without making the slide anti-MCP
   Message: a local CLI is natural when the tool belongs with the capability
   Visual: standardized terminal window plus discoverable/local/versioned callouts
   Notes: MCP nuance matters, but keep it as one contrast note instead of a debate slide

09 Serious skills have a release shape
   Role: make quality gates feel like part of the package
   Message: useful skills align context, contract, and validation
   Visual: circular gate path with amber-to-green progression
   Notes: the visual should imply maturity and release readiness, not a generic process

SECTION 3: PROOF IN PRACTICE
10 Separator: Proof in Practice
   Role: move from concept into the presentation skill case study
   Message: the presentation skill is the proof
   Visual: single clean deck stack with its own identity
   Notes: do not reuse the final artifact-stack visual; the separator needs its own look

11 Alignment comes before creation
   Role: show that the skill forces deep context before slides
   Message: the first deliverable is a grounded plan
   Visual: context streams funneling into a plan output
   Notes: make the plan feel earned by context, not like ordinary chat

12 Templates provide the starting structure
   Role: show templates as incomplete software skeletons
   Message: the skill provides a starting point, not a finished deck generator
   Visual: template sheet plus downstream completion lanes
   Notes: emphasize completion downstream without overexplaining implementation

13 Examples calibrate taste
   Role: show examples as taste transfer without freezing output
   Message: examples teach judgment across orthogonal slide types
   Visual: 2x2 grid of miniature slides from one design system
   Notes: each miniature should look meaningfully different, not like repeated cards

14 Screenshots to iterate for quality
   Role: make the validation loop visible
   Message: screenshots reveal fit, hierarchy, balance, and visual story
   Visual: screenshot window with production-like slide and review loop
   Notes: the screenshot target should look like a real slide, not a placeholder box

15 One workflow creates very different decks
   Role: land that standardizing workflow does not standardize artifacts
   Message: a shared capability can still produce highly local outputs
   Visual: two different final deck stacks with visibly different content
   Notes: the artifacts must be clearly different; avoid generic empty deck stacks

CLOSE
16 Q&A
   Role: close cleanly and restate the thesis
   Message: skills equip agents with standardized capabilities
   Visual: standardized terminal ready for questions
   Notes: terminal should match the title and tools terminals
```

## Planning Notes

- The agenda names sections, not individual slides.
- Each agenda section has a separator slide with a visual concept planned before coding.
- Section separators are counted as visible slides.
- Slide blocks are for human review of story and design direction, not final wording.
- If the requested count changes, adjust the count contract first, then remap agenda sections and separators before editing slide details.
