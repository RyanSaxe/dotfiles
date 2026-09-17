/**
 * Code excerpt: the real lines from the repository, with margin notes.
 *
 * Only the requested lines render, through Pierre's renderRange, so an excerpt
 * of a 20,000-line file costs the lines it shows. The notes sit beside the
 * lines they annotate; below 720px there is no margin to sit in, so they
 * become a numbered list under the code.
 */
import { formatLocation } from "../grammar.mjs";
import { failed, themeName, whenVisible } from "../libraries.mjs";
import { fileContents, loadPierre } from "../code.mjs";

const NARROW = 720;
const GAP = 8;

export function excerpt(mount, data, context) {
  const { location, notes } = data;
  const ref = location.ref ?? context.ref;
  mount.classList.add("excerpt");

  const header = document.createElement("header");
  const path = document.createElement("button");
  path.className = "excerpt-path";
  path.dataset.target = "excerpt";
  path.dataset.location = formatLocation(location);
  path.textContent = formatLocation(location);
  path.onclick = () => context.open({ ...location, ref });
  const meta = document.createElement("span");
  meta.className = "muted";
  meta.textContent = `@ ${ref}`;
  header.append(path, meta);

  const body = document.createElement("div");
  body.className = "excerpt-body";
  const code = document.createElement("div");
  code.className = "excerpt-code";
  const margin = document.createElement("ol");
  margin.className = "excerpt-notes";
  body.append(code, margin);
  mount.replaceChildren(header, body);

  let view = null;
  const place = () => {
    // Line each note up with its row, then push it down if the note above it
    // is tall enough to reach it. Reading the rows' offsets is the only way to
    // know where Pierre put them, and a note that covers its neighbour is
    // worse than one sitting a few pixels below its line.
    const narrow = mount.clientWidth < NARROW;
    mount.classList.toggle("narrow", narrow);
    const shadow = code.querySelector("diffs-container")?.shadowRoot;
    const origin = code.getBoundingClientRect().top;
    let floor = 0;
    for (const item of margin.children) {
      if (narrow || !shadow) {
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
    margin.style.minHeight = narrow ? "" : `${floor}px`;
  };

  const stop = whenVisible(mount, async () => {
    try {
      const contents = await fileContents(location.path, ref);
      const { File } = await loadPierre();
      const total = contents.content.split("\n").length;
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
        theme: themeName() === "dark" ? "github-dark" : "github-light",
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
        number.className = "note-number";
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
