window.addEventListener("plan:page", ({ detail: { element } }) => {
  element.querySelectorAll(".change-review").forEach((root) => {
    const viewer = root.querySelector(".change-view");
    const error = root.querySelector("[data-diff-error]");
    const buttons = root.querySelectorAll("[data-diff-style]");
    let input;
    const fail = (reason) => {
      error.textContent = reason.message || "Diff renderer unavailable.";
      error.hidden = false;
    };
    try {
      input = JSON.parse(root.querySelector("[data-diff-input]").value);
      for (const source of root.querySelectorAll("[data-diff-source]"))
        source.textContent = input[source.dataset.diffSource];
    } catch (reason) {
      fail(reason);
      return;
    }
    const render = async (diffStyle) => {
      try {
        await window.planUI.diff(viewer, input, { diffStyle });
        for (const button of buttons)
          button.setAttribute(
            "aria-pressed",
            String(button.dataset.diffStyle === diffStyle),
          );
      } catch (reason) {
        fail(reason);
      }
    };
    for (const button of buttons)
      button.onclick = () => render(button.dataset.diffStyle);
    render("split");
  });
});
