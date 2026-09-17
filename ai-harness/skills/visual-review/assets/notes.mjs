/**
 * The note registry and the markers that show them.
 *
 * Notes come from two places: a `notes` fence, which annotates a file or a
 * diff without showing it, and the margin notes on a code excerpt. Both land
 * in one map keyed by target, so a note written beside an excerpt on page two
 * is also a marker in the gutter when the whole file opens later.
 */
import { targetKey } from "./grammar.mjs";

export function createNoteRegistry() {
  const pages = new Map();

  /**
   * Replace everything one page contributed. A republished page must not
   * leave the notes it used to carry behind.
   */
  function setPage(pageKey, { notes = [], blocks = [], from = {} } = {}) {
    const collected = [];
    for (const fence of notes)
      for (const note of fence.notes)
        collected.push({ key: fence.key, ...note, from });
    for (const block of blocks) {
      if (block.name !== "code" || !block.data) continue;
      const key = targetKey({
        kind: "file",
        path: block.data.location.path,
        ref: block.data.location.ref,
      });
      for (const note of block.data.notes)
        collected.push({
          key,
          start: note.line,
          end: note.line,
          side: null,
          text: note.text,
          from,
        });
    }
    if (collected.length) pages.set(pageKey, collected);
    else pages.delete(pageKey);
  }

  /**
   * Every note on one target, in line order and numbered from one. The number
   * is what a marker shows, so it has to be stable for a given target rather
   * than counted per page.
   */
  function forTarget(key) {
    const found = [];
    for (const collected of pages.values())
      for (const note of collected) if (note.key === key) found.push(note);
    found.sort(
      (a, b) =>
        a.start - b.start || a.end - b.end || a.text.localeCompare(b.text),
    );
    return found.map((note, index) => ({ ...note, n: index + 1 }));
  }

  return {
    setPage,
    forTarget,
    targets: () =>
      [...new Set([...pages.values()].flat().map((note) => note.key))].sort(),
    clear: () => pages.clear(),
  };
}

/**
 * Put a numbered marker in the gutter of every annotated line, and show the
 * open one beneath its line.
 *
 * Pierre owns the rows, so the marker is appended to the gutter cell in
 * `onPostRender` and re-appended after every render. The open note is supplied
 * through `setLineAnnotations`, which is what makes it take vertical space
 * between the lines rather than covering them.
 */
export function createMarkers({ view, container, notes, onOpen, navigate }) {
  let open = null;

  const card = (note) => {
    const element = document.createElement("div");
    element.className = "note-card";
    const text = document.createElement("div");
    text.textContent = note.text;
    element.append(text);
    if (note.from?.pageTitle) {
      const source = document.createElement("button");
      source.className = "note-from";
      source.textContent = `from ${note.from.questionTitle} › ${note.from.pageTitle}`;
      source.onclick = () => navigate?.(note.from);
      element.append(source);
    }
    return element;
  };

  function toggle(note) {
    open = open?.n === note.n ? null : note;
    view.setLineAnnotations(
      open
        ? [
            open.side
              ? { side: open.side, lineNumber: open.start, metadata: open }
              : { lineNumber: open.start, metadata: open },
          ]
        : [],
    );
    view.rerender();
    onOpen?.(open);
  }

  function marker(note) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "note-marker";
    button.dataset.note = String(note.n);
    button.textContent = String(note.n);
    button.title = `Note ${note.n}`;
    button.onclick = (event) => {
      event.stopPropagation();
      toggle(note);
    };
    return button;
  }

  /** Re-attach markers after a render; Pierre rebuilds its rows each time. */
  function inject() {
    const shadow = container.querySelector("diffs-container")?.shadowRoot;
    if (!shadow) return;
    for (const note of notes) {
      const side =
        note.side === "deletions"
          ? '[data-line-type^="change-deletion"]'
          : note.side === "additions"
            ? '[data-line-type^="change-addition"]'
            : "";
      const cell = shadow.querySelector(
        `[data-gutter] [data-column-number="${note.start}"]${side}`,
      );
      // Two notes may sit on one line, so each gets its own marker. The
      // guard is against re-injecting the same note after a render, not
      // against a second note on the same row.
      if (cell && !cell.querySelector(`.note-marker[data-note="${note.n}"]`))
        cell.append(marker(note));
    }
  }

  return {
    inject,
    renderAnnotation: (annotation) => card(annotation.metadata),
    /** ] and [ step through the markers in the order they appear. */
    step(delta) {
      if (!notes.length) return;
      const at = open ? notes.findIndex((note) => note.n === open.n) : -1;
      const next = notes[Math.max(0, Math.min(notes.length - 1, at + delta))];
      if (next && next.n !== open?.n) toggle(next);
    },
    close() {
      if (open) toggle(open);
    },
    get open() {
      return open;
    },
  };
}
