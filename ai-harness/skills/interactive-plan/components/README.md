# Writing a component

A component directory holds `markup.html`, and `styles.css` and
`behavior.mjs` when the component needs them. The builder reads those three
files and nothing else, so a directory may also hold a helper the agent
runs, such as `before-after/diff.mjs`. [index.md](index.md) is the
catalog a plan author reads.

## Behavior

`behavior.mjs` registers the component with `planUI.define`, and the frame
runs every registration over each page as it renders:

```js
planUI.define("scope-checklist", {
  match: ".scope-list[data-multiselect]",
  setup(list, { page, planUI }) {
    // Runs once per matching element, on every page render.
  },
});
```

`match` is a CSS selector. `setup` runs once for each element the selector
finds. A failure prints in the element's place and leaves the rest of the
page rendered. A `setup` that returns a promise is awaited before the frame
restores the scroll position.

A page renders by replacing `#page-content`, so `setup` runs again on every
visit. Hold nothing between renders. Keep a viewing preference the reader
chose, such as a layout, in `planUI.prefs`, keyed by `page.id` and the
element's own ID so two of the same component on a page stay separate.

The frame supplies the shared parts a component uses directly: `figure()`
for a figure's header, actions and caption, `copyButton()`, `failed()` for a
renderer error in place, `script()` with the pinned CDN locations in
`libraries`, `color()` for a token's current value, and `readData()` for a
JSON array in a data attribute. A component calls another through `planUI`:
the prototype renders its source fold with `planUI.enhance`, and the chart
calls `planUI.chart`.

Set `data-kind` on the component's root to a singular noun that follows
"this", so the comment control names it.

## Styles

`styles.css` needs no wrapper. The builder writes it into a cascade layer
that beats page CSS and `frame.css`, so a component sets its own type and
spacing without fighting a frame selector. Use the design tokens in
[frame.md](../references/frame.md).

A component that holds authored content gives it a slot, and the frame
supplies the space around it. The slot zeroes the outer margin of its first
and last child, so a `<pre>`, a `<div>`, a figure and a table all sit the
same distance from the slot's edges.

| Component       | Slot                      |
| --------------- | ------------------------- |
| visual-decision | `.visual-option > figure` |
| comparison      | `.comparison-content`     |
| before-after    | `.change-content`         |
| behavior-cases  | `.behavior-case > div`    |

## Components of the user's own

The builder also reads `$XDG_CONFIG_HOME/interactive-plan/components/`, with
`~/.config` as the fallback. A directory there with the same name replaces
the skill's component, and a skill update never touches it. To keep a
page's one-off shape, write `markup.html`, `styles.css` and `behavior.mjs`
there and move the code out of the page's files.

## Checking a change

The fixture under `scripts/fixture/` renders every component, and its
`slots` page holds each slot against every kind of element. Open it in both
themes, at a wide window and at 375px, after changing a component.
