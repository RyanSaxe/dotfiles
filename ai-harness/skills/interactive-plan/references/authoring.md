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
Use `kind: "exploration"` when reopening choices; it disables acceptance.
`feedback` is reserved. With structured agreements, `agreed` is also reserved.
Legacy authored `agreed` pages remain usable when no structured record is present.

The builder escapes literal `<` as `\u003c` inside the JSON script. If editing
assembled HTML directly, do the same when content could contain
`</script>`. The page `html` is trusted agent-authored HTML and is not a Markdown
string. User notes are rendered as text by the frame. Do not inject feedback
into executable HTML or scripts.

Leave `session-config` in the source. The helper injects session identity when
publishing. Never put the agent token into the page.

## Agreement record

Add a top-level `agreements` array, independent of `pages`:

```json
{
  "agreements": [
    {
      "id": "batch-errors",
      "title": "Per-item failures",
      "html": "<p>Return one result per input, including individual failures.</p>",
      "source": "User selected per-item results in revision 2.",
      "href": "./batch-prediction.2.html?target=failure-options#interface",
      "change": "new"
    }
  ]
}
```

Each entry requires a stable unique `id`, `title`, `html`, and `source` text.
Use `file` instead of `html` to reuse an authored fragment. A short paragraph is
enough for routine decisions; preserve exact code or visual details when needed.
Do not regenerate settled entries or rebuild previews merely to fill the record.

State defaults to `agreed`. After reading feedback, mark an affected entry
`reopened` when another decision is needed. The frame displays “Revisiting”;
retain the previous wording until resolved. Update the same ID when settled.
Use `retired` with an explanation when a decision no longer applies; those
entries appear under “No longer applies.” Topic changes alone do not retire
agreements. The helper validates structure, not whether the user agreed.

Optional `change: "new"` or `"updated"` marks this publication only. Remove old
change markers on the next publication. A recommendation is not an agreement.
Read browser submissions and conversation answers before editing the record.

Optional `href` opens the immutable source revision in a new tab. Use relative
or HTTP(S) URLs; executable schemes are rejected. Conversation-only decisions
need no link. Give important proposal components stable element IDs. The frame
supports `?target=ELEMENT_ID#PAGE_ID`, opens containing details, and focuses the
target; missing targets and older snapshots retain page-level navigation.

The frame renders the index, detail pane, and quiet Add note action. Entry notes
carry `agreementId`, title, and revision through the existing draft and explicit
submission flow. Comments do not change agreement state automatically. An empty
record still has an Agreed page. Final plans incorporate decisions into their
steps; source links and the record do not replace a self-contained handoff.

## Shared UI

Retain the checked editor-inspired light/dark tokens, 235px desktop sidebar,
thin blue active-item rule, standard theme control, and topic-based feedback.
The sidebar separates proposal pages from Agreed and Feedback with a divider.
It shows the viewed revision, not operational status. Review & submit opens
Feedback without sending it. Receipt and agent status appear beside Submit.
Final plans use the same frame. Do not create competing theme controls: the
browser preference applies until an explicit choice, remembered in a host-only
cookie across local ports. Feedback drafts remain revision- and session-scoped.

The frame supplies `.panel`, `.two`, `.row`, `.btn`, `.section-head`,
`.recommendation`, and ordinary headings, tables, code, and images. They are
conveniences, not a required page grammar. Use freely composed HTML for the
actual work. Do not force equal-sized decision cards or one decision per page.

Blue is the general accent. Green means success, red means danger or
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
