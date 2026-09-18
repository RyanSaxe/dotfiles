/**
 * The figure shell every block that shows a file, a diff, a chart, or a
 * diagram sits in: a head with the name in bold, a muted detail, and one
 * action on the right; the block's own body; an optional caption.
 *
 * A figure with nothing to name keeps a head that says only what kind of
 * figure it is, shown when the code pane is wide and figures collapse to
 * their heads.
 */
export function figure(mount, { kind, name, detail, action, caption } = {}) {
  mount.classList.add("figure");
  const head = document.createElement("div");
  head.className = "figure-head";
  const label = document.createElement("span");
  if (name) {
    const strong = document.createElement("b");
    strong.textContent = name;
    label.append(strong);
    if (detail) label.append(` · ${detail}`);
  } else {
    label.textContent = detail ?? kind ?? "";
    if (!detail) mount.classList.add("headless");
  }
  head.append(label);
  if (action) head.append(action);
  const body = document.createElement("div");
  body.className = "figure-body";
  mount.replaceChildren(head, body);
  if (caption) {
    const note = document.createElement("div");
    note.className = "figure-caption";
    note.textContent = caption;
    mount.append(note);
  }
  return { head, body };
}
