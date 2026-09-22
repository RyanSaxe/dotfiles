/* The count over a list that starts empty. */
planUI.define("scope-checklist", {
  match: ".scope-list[data-multiselect]",
  setup(list) {
    const line = list.querySelector(".scope-count");
    const boxes = [...list.querySelectorAll(".scope-check")];
    if (!line || !boxes.length) return;
    const update = () => {
      const checked = boxes.filter((box) => box.checked).length;
      line.innerHTML = `<b>${checked} of ${boxes.length}</b> included`;
    };
    for (const box of boxes) box.addEventListener("change", update);
    update();
  },
});
