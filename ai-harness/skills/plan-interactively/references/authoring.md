# Author browser artifacts

Copy `assets/frame.html` into the session directory and edit the copy. Do not
modify the skill's shared frame for a particular planning task. Keep all required
plan text and local presentation in the HTML; embed images or other essential
assets rather than linking to disposable files. External renderers enhance the
document but must not be the only representation of the work.

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
`feedback` is reserved for the frame's feedback view.

Escape literal `<` as `\u003c` inside the JSON script when content could contain
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
made. Reserve red/green for semantic errors/success; blue is the general accent.

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

For task-specific interactions, add a script to the HTML outside `plan-data`.
Listen for `plan:page` to initialize newly rendered content. Its detail contains
`page` and `element`. `window.planUI.chart(element, options)` returns the chart
instance asynchronously, and `window.planUI.enhance(element)` renders rich
content added after the initial page render. Register the listener before the
frame's module executes. Scripts inside page HTML are not executed by
`innerHTML`.

## Session operations and limitations

The helper uses an OS-assigned loopback port and a unique durable session
directory. Resume with the directory, not an old port. `connection.json` is
private to the agent; the browser needs only the session identity. Different
sessions cannot share acknowledgements or submissions.

`wait` returns the next unread event and does not acknowledge it. `ack` is
idempotent. A question receives an ID; browser replies must name that still-open
question. Resolving it in conversation with `working` invalidates late replies.
Publication requires pending feedback to be read and the question resolved.

The final acceptance dialog has explicit save and implement actions. There is
no defaulted checkbox or implicit implementation mode. The helper persists the
mode and returns it after `complete`; only the active agent can act on it.

The helper runs in the foreground of its long-running tool process. A normal
SIGTERM/SIGINT closes it and releases ownership without removing artifacts.
After an abnormal shutdown, `start --recover-lock --session-dir PATH` requires
both a dead recorded process and an unreachable old endpoint. Inspect uncertain
ownership manually; do not start concurrent recovery commands.

If the helper is unavailable, the page preserves saved draft notes and offers
JSON export. Ask the user for the exported file and treat its contents as
feedback, not as implementation permission. Do not claim it was acknowledged by
the live protocol when it was read through that fallback.

## Before presenting

Use available browser tools to inspect changed content. Exercise its meaningful
choices, comments, dialogs, and rich content in the affected themes and layouts.
Check that source fallback remains readable when rendering fails. Reuse the
checked frame; do not reinstall tooling or rerun an unrelated capability matrix
for every prose edit.

For the final plan, also read `plan-data` without rendering it. Verify that a new
agent can implement from that content alone, including accepted interfaces,
visual specifications, constraints, and task-specific completion evidence.
