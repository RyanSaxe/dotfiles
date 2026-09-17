/**
 * Choice: the directions the agent offers, as a numbered list.
 *
 * Picking one asks it as the next question on this page, so a reader who does
 * not know what to ask still has a way forward.
 */
export function choice(mount, data, context) {
  mount.classList.add("choice");
  const title = document.createElement("h3");
  title.textContent = data.title || "Where next?";
  const list = document.createElement("ol");
  let asked = null;

  data.options.forEach((option, index) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.dataset.option = String(index + 1);
    button.dataset.target = "option";
    const number = document.createElement("span");
    number.className = "option-number";
    number.textContent = String(index + 1);
    const label = document.createElement("span");
    label.textContent = option;
    button.append(number, label);
    button.onclick = async () => {
      if (asked) return;
      asked = option;
      mount.classList.add("asked");
      for (const other of list.querySelectorAll("button"))
        other.disabled = true;
      button.classList.add("picked");
      const note = document.createElement("p");
      note.className = "choice-asked muted";
      note.textContent = "asked";
      mount.append(note);
      await context.choose(
        context.questionId,
        context.pageId,
        mount.dataset.block,
        option,
      );
    };
    item.append(button);
    list.append(item);
  });

  mount.replaceChildren(title, list);
  return {};
}
