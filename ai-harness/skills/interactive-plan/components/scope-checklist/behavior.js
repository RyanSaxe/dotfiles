/* The count over a list that starts empty. */
window.addEventListener("plan:page", ({ detail: { element } }) => {
  for (const list of element.querySelectorAll(
    ".scope-list[data-multiselect]",
  )) {
    const line = list.querySelector(".scope-count");
    const boxes = [...list.querySelectorAll(".scope-check")];
    if (!line || !boxes.length) continue;
    const update = () => {
      const checked = boxes.filter((box) => box.checked).length;
      line.innerHTML = `<b>${checked} of ${boxes.length}</b> included`;
    };
    for (const box of boxes) box.addEventListener("change", update);
    update();
  }
});
