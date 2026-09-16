window.addEventListener("plan:page", ({ detail: { element } }) => {
  element.querySelectorAll(".scope-check").forEach((input) => {
    const row = input.closest("[data-choice]");
    input.checked =
      row
        .querySelector('[data-value="Include"]')
        .getAttribute("aria-pressed") === "true";
    input.onchange = () => {
      row
        .querySelector(
          input.checked ? '[data-value="Include"]' : '[data-value="Defer"]',
        )
        .click();
    };
  });
});
