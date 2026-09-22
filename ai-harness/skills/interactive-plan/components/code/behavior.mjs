/* A code block: syntax colour, line numbers, a focused range, and a note
   on a line. Shiki is loaded once, from the location the frame pins. */
let shikiTask;
/* The source before Shiki rewrote it, so Copy gives the file's text. */
const sources = new WeakMap();
const noteBubble =
  '<svg viewBox="0 0 16 14" width="15" height="14" aria-hidden="true">' +
  '<path d="M2 1.5h12a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H7l-3 2.5V9.5H2a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1Z" ' +
  'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>';
let codeNote = null;
function closeCodeNote() {
  if (!codeNote) return;
  codeNote.mark.setAttribute("aria-expanded", "false");
  codeNote.popup.hidePopover?.();
  codeNote.popup.remove();
  codeNote = null;
}
/* The popover is fixed to the window, so it follows its line while the page
   moves under it, and any click that is not on a note closes it. */
function followCodeNote() {
  codeNote?.place();
}
document.addEventListener("click", closeCodeNote);
document.addEventListener("scroll", followCodeNote, {
  capture: true,
  passive: true,
});
window.addEventListener("resize", followCodeNote);
/* A note stands outside the figure it belongs to: the figure is
   overflow: hidden, and a note on the last line would be cut in half. */
function showNote(element, line, mark, note) {
  const popup = document.createElement("div");
  popup.className = "code-popup";
  popup.popover = "manual";
  const label = document.createElement("b");
  label.textContent = `Line ${note.line}`;
  const text = document.createElement("span");
  text.textContent = note.text;
  const shut = document.createElement("button");
  shut.type = "button";
  shut.className = "code-popup-close";
  shut.textContent = "\u2715";
  shut.onclick = closeCodeNote;
  popup.append(label, text, shut);
  ($("page-content") || element).append(popup);
  popup.showPopover();
  const place = () => {
    const box = line.getBoundingClientRect();
    const host = (
      element.closest(".figure") || element
    ).getBoundingClientRect();
    const width = Math.min(460, host.width - 40);
    popup.style.width = `${Math.round(width)}px`;
    popup.style.left = `${Math.round(
      Math.min(Math.max(8, host.left + 40), window.innerWidth - width - 8),
    )}px`;
    const below = box.bottom + 6;
    popup.style.top = `${Math.round(
      below + popup.offsetHeight > window.innerHeight - 8
        ? Math.max(8, box.top - popup.offsetHeight - 6)
        : below,
    )}px`;
  };
  place();
  mark.setAttribute("aria-expanded", "true");
  return { mark, popup, place };
}
function addNote(element, lines, note) {
  const line = lines[note.line - 1];
  if (!line || line.dataset.noted) return;
  line.dataset.noted = "true";
  line.classList.add("has-note");
  const mark = document.createElement("button");
  mark.type = "button";
  mark.className = "code-note-mark";
  mark.innerHTML = noteBubble;
  mark.setAttribute("aria-expanded", "false");
  mark.setAttribute("aria-label", `Note on line ${note.line}`);
  const toggle = (event) => {
    event.stopPropagation();
    const again = codeNote?.mark === mark;
    closeCodeNote();
    if (!again) codeNote = showNote(element, line, mark, note);
  };
  mark.onclick = toggle;
  line.onclick = toggle;
  line.prepend(mark);
}
/* The fade at the right edge, while there is a line the column cannot show.
   The pre is the box that scrolls, not the element carrying data-language:
   the frame's generic pre rule gives it overflow: auto. */
function watchCodeScroll(element) {
  const box = element.querySelector(".shiki") || element;
  const update = () => {
    const hidden = box.scrollWidth - box.clientWidth - box.scrollLeft;
    box.dataset.more = String(hidden > 2);
  };
  box.addEventListener("scroll", update, { passive: true });
  new ResizeObserver(update).observe(box);
  update();
}
/* Line numbers, the focused range and the notes, once Shiki has written its
   lines. Every part is optional and a block with none of the attributes is
   the block the skill always had. */
function decorateCode(element) {
  const lines = [...element.querySelectorAll(".shiki code .line")];
  if (!lines.length) return;
  const [from, to] = (element.dataset.lines || "")
    .split("-")
    .map((value) => Number(value));
  if (from)
    lines.forEach((line, index) =>
      line.classList.toggle(
        "in-focus",
        index + 1 >= from && index + 1 <= (to || from),
      ),
    );
  for (const note of readData(element.dataset.notes))
    addNote(element, lines, note);
  watchCodeScroll(element);
}
async function renderCode(element) {
  /* A newline against either tag gives Shiki an empty first or last line,
     which the numbers make visible as a line the file does not have. */
  const source = element.textContent
    .replace(/^\n/, "")
    .replace(/\n[ \t]*$/, "");
  sources.set(element, source);
  try {
    shikiTask ||= import(libraries.shiki);
    const { codeToHtml } = await shikiTask;
    const html = await codeToHtml(source, {
      lang: element.dataset.language,
      themes: syntaxThemes,
      defaultColor: false,
    });
    if (element.isConnected) {
      element.innerHTML = html;
      decorateCode(element);
    }
  } catch (error) {
    failed(element, error);
  }
}
planUI.define("code", {
  match: "[data-language]",
  setup(element) {
    if (element.dataset.file !== undefined || element.dataset.caption) {
      const meta = document.createElement("span");
      meta.textContent = element.dataset.language;
      figure(element, {
        title: element.dataset.file,
        meta,
        actions: [
          copyButton(() => sources.get(element) ?? element.textContent),
        ],
        caption: element.dataset.caption,
        kind: "code",
      });
    }
    return renderCode(element);
  },
});
