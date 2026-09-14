# Author browser artifacts

Author pages as ordinary HTML files alongside a JSON manifest in the session
directory. Add custom CSS and JavaScript files as needed. You have full freedom
to compose components and interactions; the shared frame supplies navigation,
themes, feedback, and acceptance, not a fixed content grammar.

Build a standalone artifact with the dependency-free Node helper:

```sh
node scripts/build.mjs SOURCE.json ARTIFACT.html
```

The output must be a new filename. The helper combines `assets/frame.html`,
`frame.css`, and `frame.js` with your content. Do not modify shared skill assets
for a particular task. Essential images and other local resources must be
embedded; the builder does not bundle linked files or JavaScript imports.
External renderers must not be the only representation of the work.

The source manifest uses the content contract below, with a page's `file`
instead of `html` to read a separate HTML file. Optional top-level `css` and
`js` name your custom files. All paths resolve relative to the manifest:

```json
{
  "artifactId": "batch-prediction",
  "revision": "1",
  "kind": "exploration",
  "title": "Batch prediction",
  "css": "proposal.css",
  "js": "proposal.js",
  "pages": [
    { "id": "interface", "title": "Interface", "file": "interface.html" }
  ]
}
```

Omit `css` or `js` when unnecessary. The builder embeds page contents in
`plan-data`, so the final handoff does not depend on these source files.

## Content contract

The `plan-data` JSON script is both the renderer's input and the semantic handoff:

```json
{
  "artifactId": "batch-prediction",
  "revision": "1",
  "kind": "exploration",
  "title": "Batch prediction",
  "pages": [
    {
      "id": "interface",
      "title": "Prediction interface",
      "html": "<p>Proposed interface and alternatives.</p>"
    }
  ]
}
```

Use `kind: "plan"` only for the actual final plan. Its first page has ID
`overview`; the remaining pages describe implementation steps. IDs contain
letters, digits, underscores, or hyphens; revisions also allow periods. Keep
IDs stable for a continuing artifact, and use a new revision for every publish.
Exploration and plan are artifact types, not irreversible phases. To reopen a
choice during final review, publish a focused exploration with a descriptive
title such as "Exploring batch behavior" and a link to the prior plan snapshot.
Keep acceptance hidden by using `kind: "exploration"`. After alignment, publish
a complete new `plan` revision, not an addendum requiring the old discussion.
`feedback` is reserved for the frame's feedback view.

The builder escapes literal `<` as `\u003c` inside the JSON script. If editing
assembled HTML directly, do the same when content could contain
`</script>`. The page `html` is trusted agent-authored HTML and is not a Markdown
string. User notes are rendered as text by the frame. Do not inject feedback
into executable HTML or scripts.

Leave `session-config` in the source. The helper injects session identity when
publishing. Never put the agent token into the page. Do not copy the prototype's
fixed port, paths, session state, example content, or competing theme choices.

## Shared UI

Retain the checked editor-inspired light/dark tokens, 235px desktop sidebar,
thin blue active-item rule, standard theme control, and topic-based feedback.
The sidebar shows the viewed revision, not operational status. Final plans use
the same frame; only their content and navigation entries change.

The frame supplies `.panel`, `.two`, `.row`, `.btn`, `.section-head`,
`.recommendation`, and ordinary headings, tables, code, and images. They are
conveniences, not a required page grammar. Use freely composed HTML for the
actual work. Do not force equal-sized decision cards or one decision per page.

Proposals should expose meaningful differences, with a recommendation and its
reason where useful. Keep labels short and prose concrete. Avoid filler,
redundant subtitles, self-reference, or discussion about how this artifact was
made. Blue is the general accent. Green means success, red means danger or
failure, and amber means attention. Each theme provides `--success`, `--danger`,
and `--attention`, with `-bg` and `-border` variants. Do not color recommendations
green or alternatives red merely to indicate preference. Include a visible
label or icon so meaning does not depend on color alone:

```html
<p class="notice" data-tone="attention">Requires review: migration downtime.</p>
```

## Choices and comments

Use stable choice IDs and human-readable labels. A click adds a choice to the
local draft; only Submit feedback sends it.

```html
<p class="recommendation">
  I recommend one result per input so callers can retry failures independently.
</p>
<div data-choice="failure-mode" data-label="Batch failure behavior">
  <button data-value="Per-item results">Per-item results</button>
  <button data-value="Reject batch">Reject the batch</button>
</div>
<button class="btn" data-comment="Error representation">Comment</button>
```

You may place choice buttons alongside unequal prototypes, code alternatives,
or a diagram. For custom controls, call `window.planUI.comment(anchor, quote)`.
Page comments and text-selection comments work without additional authoring.

## Rich content

The frame owns pinned CDN URLs and integrity values. Load only the capabilities
used in a page. Do not vendor packages or run npm installation for an artifact.
Shiki's ESM import and Mermaid's dependency graph do not gain full integrity
verification merely from version pinning. CDN rendering needs a connection.

Code fences use Shiki with on-demand language grammars and dual light/dark
themes. HTML-escape the source code:

```html
<div data-language="python">
  def predict_batch(items: list[Input]) -&gt; list[Prediction]: ...
</div>
```

The language comes from `data-language`, not a fixed whitelist. Unsupported
languages preserve source and report renderer failure; choose an appropriate
alternative when the task requires one.

KaTeX handles inline and display math. Backslashes must be escaped again when
this HTML is inside JSON:

```html
<div data-math="display">F_\beta=(1+\beta^2)\frac{PR}{\beta^2P+R}</div>
```

Mermaid handles diagrams. Preserve its source in the page content. Use native
SVG when it makes a diagram clearer; Mermaid is a default, not a restriction.

```html
<div data-diagram>flowchart LR Input --> Validate --> Predict</div>
```

Apache ECharts accepts an option object as the element's JSON text:

```html
<div data-chart>
  { "tooltip": {"trigger": "axis"}, "xAxis": {"type": "category", "data":
  ["0.2", "0.5", "0.8"]}, "yAxis": {"type": "value"}, "series": [{"type":
  "line", "data": [0.61, 0.78, 0.9]}] }
</div>
```

For task-specific interactions, use the manifest's `js` file. It is embedded as
a classic script before the frame's module, outside `plan-data`.
Listen on `window` for `plan:page` to initialize newly rendered content. Its detail contains
`page` and `element`. `window.planUI.chart(element, options)` returns the chart
instance asynchronously, and `window.planUI.enhance(element)` renders rich
content added after the initial page render. Register the listener before the
frame's module executes. Scripts inside page HTML are not executed by
`innerHTML`.

```js
window.addEventListener("plan:page", ({ detail: { element } }) => {
  const button = element.querySelector("[data-preview]");
  if (button) button.onclick = () => button.classList.toggle("expanded");
});
```

## Before presenting

Use available browser tools to inspect changed content. Exercise its meaningful
choices, comments, dialogs, and rich content in the affected themes and layouts.
Check that source fallback remains readable when rendering fails. Reuse the
checked frame; do not reinstall tooling or rerun an unrelated capability matrix
for every prose edit.

For the final plan, also read `plan-data` without rendering it. Verify that a new
agent can implement from that content alone, including accepted interfaces,
visual specifications, constraints, and task-specific completion evidence.
