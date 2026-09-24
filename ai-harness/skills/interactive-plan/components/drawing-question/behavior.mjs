planUI.define("drawing-question", {
  match: "[data-drawing-question]",
  setup(card, { planUI }) {
    const id = card.dataset.drawingQuestion;
    const button = card.querySelector("[data-draw]");
    const image = card.querySelector(".drawing-preview");
    const error = card.querySelector("[data-drawing-error]");
    if (!button || !image || !error) return;
    const show = (answer) => {
      image.hidden = !answer;
      if (answer)
        image.src = `${base}/api/upload/${encodeURIComponent(answer.previewId)}`;
      button.textContent = answer ? "Edit drawing" : "Draw answer";
    };
    show(planUI.drawing(id));
    button.disabled = planUI.mode !== "live" || !online;
    button.onclick = async () => {
      error.hidden = true;
      try {
        await planUI.draw(id, card.dataset.label, card.id, show);
      } catch (cause) {
        error.textContent =
          cause.message || "Could not open the drawing editor.";
        error.hidden = false;
      }
    };
  },
});
