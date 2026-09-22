/* The Answer button and the answered card. planUI.prefs keeps the state for
   this session and revision, so a reload comes back answered. */
window.addEventListener("plan:page", ({ detail: { element, page } }) => {
  for (const card of element.querySelectorAll(".question[data-question]")) {
    const area = card.querySelector("textarea");
    const text = card.querySelector(".answer-text");
    const save = card.querySelector("[data-answer]");
    const edit = card.querySelector("[data-edit]");
    if (!area || !text || !save || !edit) continue;
    const key = `answered:${page.id}/${card.dataset.question}`;
    const show = (answered) => {
      card.dataset.state = answered ? "answered" : "open";
      text.textContent = area.value;
      text.hidden = !answered;
      area.hidden = answered;
      save.hidden = answered;
      edit.hidden = !answered;
    };
    save.disabled = !area.value.trim();
    area.addEventListener("input", () => {
      save.disabled = !area.value.trim();
    });
    save.onclick = () => {
      window.planUI?.prefs?.set(key, "1");
      show(true);
    };
    edit.onclick = () => {
      window.planUI?.prefs?.set(key, "");
      show(false);
      area.focus();
    };
    if (window.planUI?.prefs?.get(key) && area.value.trim()) show(true);
  }
});
