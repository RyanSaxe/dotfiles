/**
 * Walkthrough: an ordered path through the code as a timeline.
 *
 * j and k move the current step and the code pane follows, so reading the
 * walkthrough is reading the files in the order they run.
 */
import { formatLocation } from "../grammar.mjs";

export function steps(mount, data, context) {
  mount.classList.add("walkthrough");
  const list = document.createElement("ol");
  let current = 0;

  const select = (index) => {
    current = Math.max(0, Math.min(data.steps.length - 1, index));
    for (const [at, item] of [...list.children].entries())
      item.classList.toggle("current", at === current);
    const step = data.steps[current];
    context.open({ ...step.location, ref: step.location.ref ?? context.ref });
  };

  data.steps.forEach((step, index) => {
    const item = document.createElement("li");
    item.dataset.target = "step";
    item.dataset.location = formatLocation(step.location);
    const text = document.createElement("span");
    text.className = "step-text";
    text.textContent = step.text;
    const where = document.createElement("span");
    where.className = "step-where";
    where.textContent = formatLocation(step.location);
    item.append(text, where);
    item.onclick = () => select(index);
    list.append(item);
  });

  mount.replaceChildren(list);
  return { select, step: (delta) => select(current + delta) };
}
