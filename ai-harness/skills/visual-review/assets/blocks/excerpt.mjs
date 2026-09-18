/**
 * Code excerpt: the real lines from the repository, with margin notes.
 *
 * Only the requested lines render, through Pierre's renderRange, so an excerpt
 * of a 20,000-line file costs the lines it shows. The notes sit beside the
 * lines they annotate; below 720px there is no margin to sit in, so they
 * stack under the code with their line numbers.
 */
import { formatLocation } from "../grammar.mjs";
import { failed, themeName, whenVisible } from "../libraries.mjs";
import { fileContents, loadPierre } from "../code.mjs";
import { figure } from "./figure.mjs";

const NARROW = 720;
const GAP = 8;

export function excerpt(mount, data, context) {
  const { location, notes } = data;
  const ref = location.ref ?? context.ref;

  const open = document.createElement("button");
  open.type = "button";
  open.className = "open";
  open.dataset.target = "excerpt";
  open.dataset.location = formatLocation(location);
  open.textContent = "Open in file";
  open.onclick = () => context.open({ ...location, ref });
  const { body } = figure(mount, {
    name: location.path,
    detail:
      location.end > location.start
        ? `lines ${location.start}–${location.end}`
        : `line ${location.start}`,
    action: open,
  });
  const code = document.createElement("div");
  code.className = "excerpt-code";
  const margin = document.createElement("ol");
  margin.className = "figure-notes";
  body.classList.add("with-notes");
  body.append(code, margin);

  let view = null;
  const place = () => {
    // Line each note up with its row, then push it down if the note above it
    // is tall enough to reach it. Reading the rows' offsets is the only way to
    // know where Pierre put them, and a note that covers its neighbour is
    // worse than one sitting a few pixels below its line.
    const stack = mount.clientWidth < NARROW;
    body.classList.toggle("stack", stack);
    const shadow = code.querySelector("diffs-container")?.shadowRoot;
    const origin = code.getBoundingClientRect().top;
    let floor = 0;
    for (const item of margin.children) {
      if (stack || !shadow) {
        item.style.removeProperty("top");
        continue;
      }
      const row = shadow.querySelector(
        `[data-column-number="${item.dataset.line}"]`,
      );
      if (!row) continue;
      const wanted = Math.max(0, row.getBoundingClientRect().top - origin);
      const placed = Math.max(wanted, floor);
      item.style.top = `${placed}px`;
      floor = placed + item.getBoundingClientRect().height + GAP;
    }
    // Positioned notes contribute no height, so the column needs its own.
    margin.style.minHeight = stack ? "" : `${floor}px`;
  };

  const stop = whenVisible(mount, async () => {
    try {
      const contents = await fileContents(location.path, ref);
      const { File } = await loadPierre();
      const total = contents.content.replace(/\n$/, "").split("\n").length;
      // Pierre counts renderRange.startingLine from zero and reads totalLines
      // as the size of the window, not the size of the file. The buffers are
      // its virtualization pre-render and add no visible lines, so the block
      // shows exactly the lines the agent asked for.
      const first = Math.max(0, Math.min(total - 1, location.start - 1));
      const count = Math.max(
        1,
        Math.min(total - first, location.end - location.start + 1),
      );
      view = new File({
        theme: { light: "github-light", dark: "github-dark" },
        themeType: themeName(),
        disableFileHeader: true,
        lineHoverHighlight: "number",
        onPostRender: () => place(),
      });
      view.render({
        file: { name: location.path, contents: contents.content },
        containerWrapper: code,
        renderRange: {
          startingLine: first,
          totalLines: count,
          bufferBefore: 0,
          bufferAfter: 0,
        },
      });
      for (const note of notes) {
        const item = document.createElement("li");
        item.dataset.line = String(note.line);
        item.dataset.target = "excerpt-note";
        const number = document.createElement("span");
        number.className = "n";
        number.textContent = String(note.line);
        const text = document.createElement("span");
        text.textContent = note.text;
        item.append(number, text);
        margin.append(item);
      }
      place();
    } catch (error) {
      failed(mount, error);
    }
  });

  const observer = new ResizeObserver(place);
  observer.observe(mount);
  const retheme = () =>
    view?.setThemeType(themeName() === "dark" ? "dark" : "light");
  window.addEventListener("vr:theme", retheme);

  return {
    dispose() {
      stop();
      observer.disconnect();
      window.removeEventListener("vr:theme", retheme);
      view?.cleanUp();
    },
  };
}
