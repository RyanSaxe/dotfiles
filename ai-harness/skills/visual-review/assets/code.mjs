/**
 * The code pane: one Pierre file view, the same renderer family the diffs and
 * excerpts use, so highlighting, line selection, and note markers share one
 * mechanism.
 *
 * A file is fetched once and held. Only one instance exists at a time; opening
 * another file disposes the first.
 */
import { libraries, module_ } from "./libraries.mjs";
import { createMarkers } from "./notes.mjs";
import { request } from "./transport.mjs";

const VIRTUALIZE_ABOVE = 3000;
const themes = { light: "github-light", dark: "github-dark" };

const files = new Map();
const panes = new WeakMap();

export const loadPierre = () => module_(libraries.pierre);

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
  pane.virtualizer?.cleanUp?.();
  panes.delete(container);
  container.replaceChildren();
}

/**
 * Render `path` at `ref` in `container`, with the cursor on `line`.
 *
 * Above VIRTUALIZE_ABOVE lines the view is virtualized, so a very large file
 * costs the rows on screen rather than the whole file.
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

  const { File, VirtualizedFile, Virtualizer } = await loadPierre();
  const existing = panes.get(container);
  if (existing?.key !== `${ref}:${path}`) {
    disposeCode(container);
    const lines = contents.content.split("\n").length;
    let markers = null;
    const shared = {
      theme: themes[theme] ?? themes.light,
      // The pane draws its own header row with the path and ref.
      disableFileHeader: true,
      enableLineSelection: true,
      lineHoverHighlight: "number",
      onLineSelected: (range) => {
        panes.get(container).selection = range;
        onCursor?.(range?.start ?? null);
        onSelect?.(range);
      },
      renderAnnotation: (annotation) => markers?.renderAnnotation(annotation),
      onPostRender: () => markers?.inject(),
    };
    let virtualizer = null;
    let view;
    if (lines > VIRTUALIZE_ABOVE) {
      virtualizer = new Virtualizer();
      virtualizer.setup(container);
      view = new VirtualizedFile(shared, virtualizer);
    } else {
      view = new File(shared);
    }
    markers = createMarkers({ view, container, notes, navigate });
    view.render({
      file: { name: path, contents: contents.content },
      containerWrapper: container,
      lineAnnotations: [],
    });
    panes.set(container, {
      key: `${ref}:${path}`,
      path,
      ref,
      view,
      markers,
      virtualizer,
      lines,
      cursor: 1,
      selection: null,
      truncated: contents.truncated,
    });
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
  pane.cursor = first;
  pane.selection = { start: first, end: last };
  pane.view.setSelectedLines({ start: first, end: last });
  container
    .querySelector("diffs-container")
    ?.shadowRoot?.querySelector(`[data-column-number="${first}"]`)
    ?.scrollIntoView({ block: "center" });
  pane.onCursor?.(first);
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

/** ] and [ in the code pane step through the notes on the open file. */
export function stepNote(container, delta) {
  panes.get(container)?.markers?.step(delta);
}

export function setTheme(container, theme) {
  const pane = panes.get(container);
  if (!pane) return;
  pane.view.setThemeType(theme === "dark" ? "dark" : "light");
  pane.markers?.inject();
}

/**
 * Flatten the open parts of the tree into the rows the browser draws.
 *
 * `read` is asked for exactly one directory per open directory, never for a
 * recursive listing, so browsing a repository costs what is on screen.
 */
export async function flattenTree(read, expanded, directory = "", depth = 0) {
  const rows = [];
  for (const entry of await read(directory)) {
    const full = directory ? `${directory}/${entry.name}` : entry.name;
    rows.push({ path: full, name: entry.name, type: entry.type, depth });
    if (entry.type === "directory" && expanded.has(full))
      rows.push(...(await flattenTree(read, expanded, full, depth + 1)));
  }
  return rows;
}
