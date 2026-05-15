# Planning Example: Software for Agents

This is a reverse plan for `examples/full-slide-examples/software-for-agents.html`.
Use it as a model for outline shape before building a full deck. It shows how to
make slide count, agenda, separators, visible copy, voiceover, and visuals line
up before coding starts.

Do not copy this deck's layout system by default. Copy the planning discipline:
count every visible slide, map agenda sections to separator slides, name the
visual job of each separator, and keep visible copy distinct from voiceover.

## Example Calibration

- Density: most slides use one claim, one dominant visual relationship, and a few labels or short lines.
- Hierarchy: titles and visuals carry the argument; supporting copy is brief and role-specific.
- Variety: the deck uses folders, quadrants, terminals, gates, template sheets, example cards, screenshot windows, and deck stacks.
- Slide/speaker split: visible copy makes the deck skimmable, while nuance and caveats belong in the presenter voiceover.
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
   Job: establish the thesis and make the deck feel CEO-ready
   Takeaway: skills package capability, not just instructions
   Visible copy: title, one thesis sentence, folder label, terminal lines
   Voiceover: why the phrase "software for agents" changes expectations
   Visual: light-blue folder equipping an agent terminal

02 Agenda
   Job: orient the room without adding explanatory copy
   Takeaway: the story has three chunks
   Visible copy: Agenda plus three section names
   Voiceover: brief setup for why the sequence starts with prompt limits
   Visual: centered agenda line with exact dot alignment

SECTION 1: PROMPT CEILING
03 Separator: Prompt Ceiling
   Job: mark the first section and set up the limitation
   Takeaway: text-only steering has a ceiling
   Visible copy: section number, section title, one short subtitle
   Voiceover: prompts help, but they do not package capability
   Visual: prompt page pressing into a ceiling line

04 Reusable prompts are not enough
   Job: show the main reusable prompt options and their gaps
   Takeaway: templates, few-shot prompts, and sub-agents each help but remain incomplete
   Visible copy: card labels, adds/gap labels, short fragments
   Voiceover: explain why these are useful but not sufficient
   Visual: prompt template card branching into few-shot and sub-agent cards

05 The missing layer is packaged capability
   Job: locate skills relative to reusable prompting patterns
   Takeaway: skills occupy the missing space of context-rich packaged capability
   Visible copy: title, axis labels, five plotted labels
   Voiceover: clarify sub-agents, custom agents, and skills without overloading the plot
   Visual: context vs. automation quadrant with skill point emphasized

SECTION 2: CAPABILITY PACKAGE
06 Separator: Capability Package
   Job: transition from missing layer to anatomy
   Takeaway: skills carry multiple capability surfaces together
   Visible copy: section number, section title, one concise subtitle, artifact labels
   Voiceover: a skill is incomplete software intended to be populated downstream
   Visual: layered artifact cards for SKILL.md, references, tools, and examples

07 A skill is a capability package
   Job: make the package shape concrete
   Takeaway: the folder can ship behavior, materials, optional software, and assurance
   Visible copy: manifest rows and four short meaning rows
   Voiceover: not every skill has every folder, but the package can carry more than prompts
   Visual: folder manifest next to meaning lanes

08 Tools can ship with the skill
   Job: answer the "why not MCP" question without making the slide anti-MCP
   Takeaway: when a tool belongs with the capability, a local CLI is a natural packaged interface
   Visible copy: terminal help lines, three benefit labels, one MCP contrast note
   Voiceover: MCP is good for isolated services; bundled CLIs fit capability-local tools
   Visual: standardized terminal window plus discoverable/local/versioned callouts

09 Serious skills have a release shape
   Job: make quality gates feel like part of the package
   Takeaway: useful skills align context, contract, and validation
   Visible copy: three gate labels and three short captions
   Voiceover: serious skills encode both behavior and checks
   Visual: circular gate path with amber-to-green progression

SECTION 3: PROOF IN PRACTICE
10 Separator: Proof in Practice
   Job: move from concept into the presentation skill case study
   Takeaway: the presentation skill is the proof
   Visible copy: section number, section title, one short subtitle
   Voiceover: the rest of the deck shows the workflow as a concrete case
   Visual: single clean deck stack with its own identity

11 Alignment comes before creation
   Job: show that the skill forces deep context before slides
   Takeaway: the first deliverable is a grounded plan
   Visible copy: title, subtitle, context labels, compressed plan label
   Voiceover: this is where the agent collects enough human judgment to avoid generic decks
   Visual: context streams funneling into a plan output

12 Templates provide the starting structure
   Job: show templates as incomplete software skeletons
   Takeaway: the skill provides a starting point, not a finished deck generator
   Visible copy: template label and three short process rows
   Voiceover: the agent completes the skeleton for the user's room
   Visual: template sheet plus downstream completion lanes

13 Examples calibrate taste
   Job: show examples as taste transfer without freezing output
   Takeaway: examples teach judgment across orthogonal slide types
   Visible copy: four example labels, short headings, one short support line where needed
   Voiceover: examples calibrate density, hierarchy, and craft rather than dictating exact layouts
   Visual: 2x2 grid of miniature slides from one design system

14 Screenshots to iterate for quality
   Job: make validation loop visible
   Takeaway: screenshots let the agent inspect fit, hierarchy, balance, and visual story
   Visible copy: title, three loop steps, one proof note
   Voiceover: render, judge, revise, then repeat until the deck is production-ready
   Visual: screenshot window with production-like slide and review loop

15 One workflow creates very different decks
   Job: land that standardizing workflow does not standardize artifacts
   Takeaway: a shared capability can still produce highly local outputs
   Visible copy: title and two artifact labels
   Voiceover: local context and user intent determine the final deck
   Visual: two different final deck stacks with visibly different content

CLOSE
16 Q&A
   Job: close cleanly and restate the thesis
   Takeaway: skills equip agents with standardized capabilities
   Visible copy: Q&A title, thesis sentence, terminal ready state
   Voiceover: invite questions around where this model fits in the audience's workflow
   Visual: standardized terminal ready for questions
```

## Planning Notes

- The agenda names sections, not individual slides.
- Each agenda section has a separator slide with a visual concept planned before coding.
- Section separators are counted as visible slides.
- Slide copy is planned as visible copy plus voiceover, so planning fields do not become slide paragraphs by accident.
- If the requested count changes, adjust the count contract first, then remap agenda sections and separators before editing slide details.
