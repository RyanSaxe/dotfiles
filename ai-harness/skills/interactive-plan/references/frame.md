# The frame

## Frame and content

The frame owns the header, the sidebar, the previous and next links at the
end of each page, the bell that lists other live sessions and closes them,
Settings (appearance and notifications), the Feedback page, the working
card (the round's steps, ticked as the agent reports them), and the preview
and read-only modes. The
header runs across the whole frame at every width and holds the revision
clock, Settings and the bell at the left, and Submit at the right, which
becomes Accept plan on a final plan that can be accepted and goes disabled
once a round is sent. The clock opens a dialog listing every revision,
newest first, with the current one ticked; choosing another one opens it.
Below 720px the sidebar is replaced by a menu button at the left of the
header, which opens the same page list in a dialog. The sidebar sits below
the header and holds Agreed, the pages, and Review comments, which opens
the Feedback page and carries the count of unsent items. The plan's title
is not in the frame: the browser tab carries it, and the revision dialog
shows it under the current revision. A page's own HTML starts below the
title and contains no `h1`; the build refuses one. The page
layout is yours. The frame provides
basic typography, tables, code, theme colors, focus, and selected-choice
states; it provides no generic card or column layouts. The builder wraps
the plan's CSS in `@scope (#page-content)`, so a rule for `body`, `:root`,
or `h1` reaches only the page's content.

The tokens and the type below are the design language of every plan: style
the components a plan makes with them and do not redefine them. Tokens, each
with a light and a dark value: `--ground` (the page behind the
frame, panels, and figure grounds), `--panel` (the frame, cards, popovers),
`--line` and `--line-strong`, `--ink`, `--muted`, `--accent` with
`--accent-ink` and `--accent-soft`, `--attention` and `--attention-bg`
(needs you), `--ok` and `--ok-bg` (sent, accepted), `--danger` and
`--danger-bg` (removed), `--code`, and `--mark` (noted text). Do not color
preferred options green or alternatives red to express preference, and add
labels so that meaning never rests on color alone.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. The frame is at most 1160px wide and centered, and the reading
column is at most 780px of text.

The frame is exactly as tall as the visible window and the page scrolls
inside it, so the window itself never scrolls and no content passes under
the header. The page and the scroll offset are remembered per session, so
the bell's jump to another session and back returns to where the reader left
off; the record carries its revision, so a new revision starts at the top of
the first page and a page the revision no longer has is ignored. Reading an
older revision draws a strip under the header that names it and links back
to the current one. Frame dialogs close on Escape
or their ✕ without submitting anything, and each takes the focus on its own
heading so no control is left ringed. Custom popups should do the same and keep unsent text. Single
keys, listed under `?`, move between sessions and pages, `j` and `k` choose
the next and previous block so that `c` comments on it, and `s` focuses
Submit so that Enter sends. Tab reaches the controls inside a block, so
keep authored controls focusable.

## Choices, comments, and answers

| Interface                            | Behavior                                                                                                                                                                                                                                       |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| data-choice                          | Stable choice-group ID. Use data-label for a readable label.                                                                                                                                                                                   |
| data-multiselect                     | Stable checklist-group ID. Use data-label for a readable question or group label.                                                                                                                                                              |
| data-question                        | Stable question ID on a section with a textarea. Use data-label for the answer's label.                                                                                                                                                        |
| data-value                           | Stable option ID on a button in data-choice, or a native checkbox in data-multiselect.                                                                                                                                                         |
| data-label on an option              | Readable option label, separate from its ID and action text. The build refuses one over 24 characters, which is what a tab strip fits; a group's data-label has no limit. Buttons fall back to their text; checkboxes fall back to data-value. |
| data-kind on a block                 | The word the comment control uses for this block, after "this". A component sets it on its own root; any other block is named from what it holds.                                                                                              |
| aria-pressed                         | Set by the frame to reflect the draft selection.                                                                                                                                                                                               |
| data-comment                         | Button action for a contextual note, using the attribute as its label; the nearest ancestor ID becomes the note's target.                                                                                                                      |
| planUI.comment(anchor, quote)        | Open a contextual comment from a custom control.                                                                                                                                                                                               |
| plan:page                            | Window event after each page render; detail has page and element.                                                                                                                                                                              |
| planUI.enhance(element)              | Render rich content added dynamically.                                                                                                                                                                                                         |
| planUI.chart(element, options)       | Return an ECharts instance asynchronously.                                                                                                                                                                                                     |
| planUI.diff(element, input, options) | Render one Git file patch through Pierre. Input contains before, after, and patch strings; options.diffStyle is split or unified.                                                                                                              |
| planUI.prefs.get(key), set(key, v)   | Remember a viewing preference for this session and artifact in the browser.                                                                                                                                                                    |
| planUI.mode                          | live, readonly, or preview.                                                                                                                                                                                                                    |

Choice clicks, checklist changes, and typed answers update the local draft;
only Submit sends it. Keep control IDs and labels the same across
revisions. Group IDs must be unique within a page across all kinds, and
option IDs within a group. Use native buttons for single choices, native
labeled checkboxes for checklists, and a textarea inside `data-question`
for answers.

Every checklist travels with a submission, including lists on pages the
user has not visited, so put checklist markup in the page HTML instead of
adding it from a script. Authored `checked` attributes set the initial
values, and the scope-checklist component ships none, so what the agent
reads is what the reviewer pressed; saved draft values take precedence. A list counts as one unsent
item once the user has changed a box, even if they put it back. An
untouched list is sent with `touched: false` and listed on Feedback as a
default afterwards. An empty set means "None selected", not unanswered.

Register custom initialization on `plan:page`. The custom JS file runs
before the frame module. Script elements inside page HTML do not execute.
Page-level, block and text-selection comments need no custom code. One
control sits at the bottom right at every width and names what it will
comment on: the selection while there is one, otherwise the block the
reader last clicked, otherwise the page. Pressing it opens the note dialog
on that target, and the note keeps the target it opened on. Clicking a
block that is not a paragraph, heading or list chooses it and draws a bar
in the column's left padding beside it; clicking the same block again,
clicking elsewhere on the page, or pressing Escape clears the choice. The
control names the block by what it is, so a decision reads "Comment on this
decision" and a table "Comment on this table". A component names itself with
`data-kind`; a block with no `data-kind` the frame cannot recognise reads
"Comment on this block". The note is filed under the name the block gives,
its heading, `data-title`, `data-file`, figure title or caption. A block that
names none of those takes the heading it sits under, then what it is, and a
name shared with another block on the page is numbered, so every note in the
Feedback list says which block it is on. A note on a block quotes nothing, so the
block keeps a muted bar in the padding the chosen one uses: the accent means
the block you are about to comment on, the muted bar means this block
already has notes.

Noted text is highlighted. Hovering it shows the note, and clicking opens
the note to edit. The count of notes on a page sits at the bottom. The
Feedback page groups items by page, with edit and remove, and holds the
overall comment. Submit, at the right of the header, sends everything
unsent at once and carries the count while any are waiting. Sent items stay
listed as sent until the next revision; items whose page or text no longer exists are listed under
the revision they came from. A submission carries `groups.choices`
(checklists with `touched`), `groups.notes`, and, when present,
`groups.answers` keyed `page/question` with `label`, `text`, and `topic`.
Its text lists untouched checklists after "Defaults, not confirmed:".

## Renderers and figures

Use the renderer that matches the content. Load only what the page needs.

| Content                                | Markup contract                                                       | Renderer |
| -------------------------------------- | --------------------------------------------------------------------- | -------- |
| Source code                            | data-language set to the actual language; HTML-escaped source as text | Shiki    |
| Inline or display math                 | data-math set to inline or display; source as text                    | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                              | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                 | ECharts  |

`data-file` on a code block adds a header with the file name, the language,
and a Copy button. Four more attributes name parts of what a figure holds:

| Attribute    | On                | What the frame does with it                                                                                                        |
| ------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| data-lines   | `[data-language]` | `"3-4"` or `"7"`. Numbers the lines, lights the range, and dims the rest until the pointer or the keyboard is on the block.        |
| data-numbers | `[data-language]` | `"true"`. Numbers the lines and dims nothing.                                                                                      |
| data-notes   | `[data-language]` | `[{"line": 3, "text": "…"}]`. A speech bubble in the gutter of each named line, opening the note in a popover. Needs no range.     |
| data-terms   | `[data-math]`     | `[{"symbol": "t", "meaning": "…", "value": "8 s"}]`. Names the formula's coloured terms under it, in the order the colours appear. |

A term takes its colour from a literal in the source, because KaTeX runs
with no `trust` option and refuses `\htmlClass`: write
`\textcolor{#1d4ed8}`, `\textcolor{#a16207}`, `\textcolor{#047857}` or
`\textcolor{#9333ea}` and the frame swaps the literal for the class that
follows the theme. Those four are a content palette, separate from
`--accent`, `--ok`, `--attention` and `--danger`, which carry meaning in the
chrome. A block that scrolls sideways fades its right edge while there is
more to see. `data-caption` on code, diagrams, and charts adds a
caption line. `data-title` on a chart adds a header. A diagram renders at
its drawn size and scrolls sideways when it is wider than the column,
shrinks to its column inside a side-by-side layout, and opens full size on
a click. Flowcharts use rank spacing 36, node spacing 28, and a title
margin of 8. The Diagrams section of the component index says what keeps a
diagram legible. Use the code renderer for source code, never a bare
block, and the [diff component](../components/index.md) for before and
after. Language grammars load on demand; an unsupported language keeps its
source and reports the failure. Escape backslashes again when math is
stored inside a JSON string.

The frame owns the pinned CDN locations and integrity values, so rendering
needs a network connection. Native SVG and custom components are still
allowed when they communicate an idea better.
