# Frame contract

This file holds what an author needs to write a page. How the frame looks
and behaves beyond that is in `assets/` and its tests, and does not belong
here.

## Page content

The frame draws the header, the navigation, the page title and the comment
control. Page HTML is a fragment that starts below the title and must not
contain an `h1`. The build rejects a page that contains one. The page
controls its own layout. The frame provides basic typography, tables, code,
theme colors, focus and selected-choice states. It does not provide generic
card or column layouts.

The builder scopes a page's CSS to that page and puts it in a cascade layer
beneath the components, so page CSS never restyles another page or a
component's chrome. `!important` still applies when a page means it.

The tokens and type below are shared design tokens for every plan. Style
the components a plan makes with them and do not redefine them. Tokens, each
with a light and a dark value: `--ground` (the page behind the frame,
panels, and figure grounds), `--panel` (the frame, cards, popovers),
`--line` and `--line-strong`, `--ink`, `--muted`, `--accent` with
`--accent-ink` and `--accent-soft`, `--attention` and `--attention-bg`
(needs you), `--ok` and `--ok-bg` (sent, accepted), `--danger` and
`--danger-bg` (removed), `--code`, and `--mark` (noted text). Do not color
preferred options green or alternatives red to express preference, and add a
label wherever color is the only sign of a meaning.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. The reading column is at most 780px wide.

## Controls

| Interface                            | Contract                                                                                                                                                           |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| data-choice                          | Stable choice-group ID on a group of native buttons. Use data-label for a readable label.                                                                          |
| data-multiselect                     | Stable checklist-group ID on a group of native labeled checkboxes. Use data-label for a readable question or group label.                                          |
| data-question                        | Stable question ID on a section with a textarea. Use data-label for the answer's label.                                                                            |
| data-drawing-question                | Stable drawing-question ID on a section using the drawing-question component. Use data-label for the answer's label.                                               |
| data-value                           | Stable option ID on a button in data-choice, or a checkbox in data-multiselect.                                                                                    |
| data-label on an option              | Readable option label. The build refuses one over 24 characters. A group's data-label has no limit. Buttons fall back to their text, and checkboxes to data-value. |
| data-kind on a block                 | The noun the comment control uses after "this", as in "Comment on this decision". A component sets it on its own root.                                             |
| data-comment                         | A button that opens a note on the nearest ancestor with an ID, using the attribute as its label.                                                                   |
| planUI.comment(anchor, quote)        | Open a note from a custom control.                                                                                                                                 |
| planUI.enhance(element)              | Render components in content a script added.                                                                                                                       |
| planUI.define(name, {match, setup})  | Register a component. See the component index.                                                                                                                     |
| planUI.chart(element, options)       | Return an ECharts instance asynchronously.                                                                                                                         |
| planUI.diff(element, input, options) | Render one Git file patch. Input has before, after and patch strings. options.diffStyle is split or unified.                                                       |
| planUI.prefs.get(key), set(key, v)   | Remember a viewing preference in the browser.                                                                                                                      |
| planUI.mode                          | live, readonly or preview.                                                                                                                                         |
| plan:page, plan:theme                | Window events after each page render (detail has page, element and revision) and after a theme change.                                                             |

The frame sets `aria-pressed` and checkbox state from the reviewer's draft,
so do not author `aria-pressed` or `checked`. Group IDs are unique within a
page across all kinds, and option IDs within a group. When a topic continues
in the next revision, keep its control IDs and labels so the reviewer's
unsent draft follows it. Put checklist markup in the page HTML, not in a
script, so every checklist is in the submission, including lists on pages
the reviewer never opened. Keep authored controls focusable.

Page JavaScript exports `setup(root, planUI)`, which the frame calls each
time the page renders. Script elements inside page HTML do not execute.

## Comments

The reviewer can comment on the page, on any block or on selected text, and
needs no authored control to do it. A note on a block is filed under the
block's heading, `data-title`, `data-file`, figure title or caption, and
otherwise under the heading above it. Give each block a distinct name so
every note identifies its block.

## Figures

Code, formulas, diagrams, charts and prototypes are components. The
[component index](../components/index.md) states their markup and
attributes. They load their renderers from pinned CDN locations, so
rendering needs a network connection.
