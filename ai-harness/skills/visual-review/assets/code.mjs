/**
 * The code pane: one Pierre file view, the same renderer family the diffs and
 * excerpts use, so highlighting, line selection, and note markers share one
 * mechanism.
 *
 * A file opens on the lines that were cited, with the rest folded above and
 * below. Each fold names what it hides and expands on demand, so a very long
 * file costs the lines the reader asked about. A file is fetched once and
 * held; only one pane instance exists at a time.
 */
import { libraries, module_ } from "./libraries.mjs";
import { createMarkers } from "./notes.mjs";
import { request } from "./transport.mjs";

const PAD = 8;
const GROW = 60;
const FIRST_OPEN = 400;
// Given both themes, Pierre switches between them with setThemeType; given
// one, it stays on it.
const themes = { light: "github-light", dark: "github-dark" };

const files = new Map();
const panes = new WeakMap();

export const loadPierre = () => module_(libraries.pierre);

/** The window to open around cited lines: the lines plus PAD each side, clipped. */
export function foldWindow(start, end, total, pad = PAD) {
  if (!start) return { from: 1, to: Math.min(total, FIRST_OPEN) };
  const last = Math.max(start, end ?? start);
  return {
    from: Math.max(1, Math.min(total, start) - pad),
    to: Math.min(total, last + pad),
  };
}

const definition =
  /^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:pub(?:\([^)]*\))?\s+)?(?:function\*?\s+\w+|def\s+\w+|class\s+\w+|fn\s+\w+|func\s+(?:\([^)]*\)\s*)?\w+|impl\b[^{]*|(?:const|let|var)\s+\w+\s*=\s*(?:async\s*)?(?:\(|function\b|\w+\s*=>))/;

/**
 * The nearest definition above `index` (zero-based), as a short label, or null.
 * Language-agnostic on purpose: a fold bar that says "function submit" is worth more
 * than a fold bar that says "344 lines", and a wrong guess costs nothing.
 */
export function enclosingSymbol(lines, index) {
  for (let i = Math.min(index, lines.length) - 1; i >= 0; i -= 1) {
    const match = lines[i].match(definition);
    if (!match) continue;
    const name = match[0]
      .replace(
        /^\s*(?:export\s+|default\s+|async\s+|pub(?:\([^)]*\))?\s+)*/,
        "",
      )
      .replace(/\s*=.*$/, "")
      .replace(/\s+/g, " ")
      .trim();
    return name.length > 48 ? `${name.slice(0, 47)}…` : name;
  }
  return null;
}

/** Committed contents for one path at one ref, fetched once per session. */
export async function fileContents(path, ref) {
  const key = `${ref}:${path}`;
  if (!files.has(key)) {
    files.set(
      key,
      request(
        `/repo/file?path=${encodeURIComponent(path)}&ref=${encodeURIComponent(ref)}`,
      )
        .then(async (response) => {
          const body = await response.json();
          if (!response.ok)
            throw new Error(body.error || "Cannot read that file");
          return body;
        })
        .catch((error) => {
          files.delete(key);
          throw error;
        }),
    );
  }
  return files.get(key);
}

export function disposeCode(container) {
  const pane = panes.get(container);
  if (!pane) return;
  pane.view.cleanUp();
  panes.delete(container);
  container.replaceChildren();
}

function foldBar(side) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `fold fold-${side}`;
  button.hidden = true;
  return button;
}

/** Fill the fold bars from the window and hide the ones with nothing to show. */
function paintFolds(pane) {
  const above = pane.window.from - 1;
  const below = pane.lines - pane.window.to;
  pane.above.hidden = above <= 0;
  pane.below.hidden = below <= 0;
  if (above > 0) {
    const symbol = enclosingSymbol(pane.source, pane.window.from - 1);
    pane.above.replaceChildren(
      Object.assign(document.createElement("b"), {
        textContent: `Show ${above} lines above`,
      }),
      ...(symbol
        ? [
            Object.assign(document.createElement("span"), {
              textContent: `· ${symbol}`,
            }),
          ]
        : []),
    );
  }
  if (below > 0)
    pane.below.replaceChildren(
      Object.assign(document.createElement("b"), {
        textContent: `Show ${below} lines below`,
      }),
    );
}

/** Re-render the window; Pierre keeps the file and swaps the rendered rows. */
/** Re-render the window; Pierre keeps the file and swaps the rendered rows. */
function renderWindow(pane) {
  pane.view.render({
    file: { name: pane.path, contents: pane.content },
    containerWrapper: pane.host,
    lineAnnotations: pane.markers.annotations(),
    renderRange: {
      // Pierre counts startingLine from zero and reads totalLines as the
      // window size; its buffers pre-render and add no visible lines.
      startingLine: pane.window.from - 1,
      totalLines: pane.window.to - pane.window.from + 1,
      bufferBefore: 0,
      bufferAfter: 0,
    },
  });
  paintFolds(pane);
}

/**
 * Show GROW more lines on one side of the window, or to the file's edge.
 *
 * Growing above keeps the line at the top of the pane where it was, so the
 * reader's place does not jump; growing below leaves the scroll alone.
 */
export function growFold(container, side) {
  const pane = panes.get(container);
  if (!pane) return;
  if (side === "above") {
    const from = Math.max(1, pane.window.from - GROW);
    if (from === pane.window.from) return;
    pane.wanted = {
      line: pane.window.from,
      top: rowTop(container, pane.window.from),
    };
    pane.window = { ...pane.window, from };
  } else {
    const to = Math.min(pane.lines, pane.window.to + GROW);
    if (to === pane.window.to) return;
    pane.window = { ...pane.window, to };
  }
  renderWindow(pane);
}

/** Grow the window until it includes `line`, then render. */
function ensureVisible(container, line) {
  const pane = panes.get(container);
  if (!pane) return;
  if (line >= pane.window.from && line <= pane.window.to) return;
  pane.window = {
    from: Math.min(pane.window.from, Math.max(1, line - PAD)),
    to: Math.max(pane.window.to, Math.min(pane.lines, line + PAD)),
  };
  renderWindow(pane);
}

/**
 * Render `path` at `ref` in `container`, opened on `line`..`end`.
 *
 * The rows on screen are the window's rows: a file costs what the reader has
 * unfolded, sixty lines at a time, so there is no separate virtualized view.
 */
export async function openFile(container, options) {
  const {
    path,
    ref,
    line,
    end,
    theme,
    notes = [],
    navigate,
    onCursor,
    onSelect,
  } = options;
  let contents;
  try {
    contents = await fileContents(path, ref);
  } catch (error) {
    disposeCode(container);
    const message = document.createElement("p");
    message.className = "placeholder";
    message.textContent = error.message;
    container.append(message);
    return null;
  }

  const { File } = await loadPierre();
  const existing = panes.get(container);
  if (existing?.key !== `${ref}:${path}`) {
    disposeCode(container);
    // A file's final newline ends its last line rather than starting another.
    const source = contents.content.replace(/\n$/, "").split("\n");
    const lines = source.length;
    const host = document.createElement("div");
    host.className = "code-host";
    const above = foldBar("above");
    const below = foldBar("below");
    container.replaceChildren(above, host, below);
    const pane = {
      key: `${ref}:${path}`,
      path,
      ref,
      container,
      host,
      above,
      below,
      notes,
      navigate,
      view: null,
      markers: null,
      source,
      content: contents.content,
      lines,
      window: foldWindow(line, end, lines),
      cursor: 1,
      selection: null,
      onCursor,
      truncated: contents.truncated,
    };
    pane.cursor = pane.window.from;
    pane.shared = {
      theme: themes,
      themeType: theme === "dark" ? "dark" : "light",
      // The pane draws its own header row with the path and ref.
      disableFileHeader: true,
      enableLineSelection: true,
      lineHoverHighlight: "number",
      onLineSelected: (range) => {
        pane.selection = range;
        onCursor?.(range?.start ?? null);
        onSelect?.(range);
      },
      renderAnnotation: (annotation) =>
        pane.markers?.renderAnnotation(annotation),
      onPostRender: () => {
        pane.markers?.inject();
        scrollToWanted(container);
      },
    };
    pane.view = new File(pane.shared);
    pane.markers = createMarkers({
      view: pane.view,
      container,
      notes,
      navigate,
    });
    panes.set(container, pane);
    above.onclick = () => growFold(container, "above");
    below.onclick = () => growFold(container, "below");
    renderWindow(pane);
  } else {
    existing.view.setThemeType(theme === "dark" ? "dark" : "light");
  }

  if (line) setCursor(container, line, end ?? line);
  return panes.get(container);
}

function setCursor(container, start, end = start) {
  const pane = panes.get(container);
  if (!pane) return;
  const first = Math.max(1, Math.min(pane.lines, start));
  const last = Math.max(first, Math.min(pane.lines, end));
  ensureVisible(container, first);
  ensureVisible(container, last);
  pane.cursor = first;
  pane.selection = { start: first, end: last };
  pane.view.setSelectedLines({ start: first, end: last });
  pane.wanted = { line: first };
  pane.onCursor?.(first);
  scrollToWanted(container);
}

/** Where a rendered row sits relative to the pane's top, or null. */
function rowTop(container, line) {
  const pane = panes.get(container);
  const row = pane?.host
    .querySelector("diffs-container")
    ?.shadowRoot?.querySelector(`[data-column-number="${line}"]`);
  if (!row) return null;
  return (
    row.getBoundingClientRect().top - container.getBoundingClientRect().top
  );
}

/**
 * Put the wanted line where it belongs: in the middle of the pane, or back
 * at the offset it had before a fold grew above it.
 *
 * Scrolls the pane rather than calling scrollIntoView, which walks up to the
 * nearest scrollable ancestor and drags the whole frame. Pierre renders its
 * rows asynchronously, so this runs again after each render until the row it
 * wants exists.
 */
function scrollToWanted(container) {
  const pane = panes.get(container);
  if (!pane?.wanted) return;
  const offset = rowTop(container, pane.wanted.line);
  if (offset === null) return;
  const target = pane.wanted.top ?? container.clientHeight / 2;
  container.scrollTop += offset - target;
  pane.wanted = null;
}

export function moveCursor(container, delta) {
  const pane = panes.get(container);
  if (!pane) return;
  setCursor(container, pane.cursor + delta);
}

export function extendSelection(container, delta) {
  const pane = panes.get(container);
  if (!pane?.selection) return;
  const end = Math.max(
    pane.selection.start,
    Math.min(pane.lines, pane.selection.end + delta),
  );
  ensureVisible(container, end);
  pane.selection = { start: pane.selection.start, end };
  pane.view.setSelectedLines(pane.selection);
}

/** What `a` and `y` act on: the selected lines, as a location. */
export function cursorLocation(container) {
  const pane = panes.get(container);
  if (!pane) return null;
  const selection = pane.selection ?? { start: pane.cursor, end: pane.cursor };
  return {
    path: pane.path,
    ref: pane.ref,
    start: selection.start,
    end: selection.end,
  };
}

export function paneFor(container) {
  return panes.get(container) ?? null;
}

/** . and , in the code pane step through the notes on the open file. */
export function stepNote(container, delta) {
  const pane = panes.get(container);
  if (!pane?.markers) return;
  const next = pane.markers.peek(delta);
  if (next) ensureVisible(container, next.start);
  pane.markers.step(delta);
}

export function setTheme(container, theme) {
  const pane = panes.get(container);
  if (!pane) return;
  pane.view.setThemeType(theme === "dark" ? "dark" : "light");
  pane.markers?.inject();
}
