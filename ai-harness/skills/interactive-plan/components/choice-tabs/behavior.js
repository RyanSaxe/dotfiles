(() => {
  function initialize(root) {
    const tabs = Array.from(
      root.querySelectorAll(
        ":scope > .choice-tabs-list > [role='tab'][data-value]",
      ),
    );
    const panels = new Map(
      Array.from(
        root.querySelectorAll(
          ":scope > .choice-tabs-canvas > [role='tabpanel'][data-choice-panel]",
        ),
        (panel) => [panel.dataset.choicePanel, panel],
      ),
    );
    if (!tabs.length) return;

    function sync() {
      const chosen = tabs.find(
        (tab) => tab.getAttribute("aria-pressed") === "true",
      );
      const active = chosen || tabs[0];
      root.dataset.preview = String(!chosen);
      for (const tab of tabs) {
        const selected = tab === active;
        tab.setAttribute("aria-selected", String(selected));
        tab.tabIndex = selected ? 0 : -1;
        const panel = panels.get(tab.dataset.value);
        if (panel) panel.hidden = !selected;
      }
    }

    root.addEventListener("click", (event) => {
      if (event.target.closest("[role='tab'][data-value]"))
        queueMicrotask(sync);
    });
    root.addEventListener("keydown", (event) => {
      const tab = event.target.closest("[role='tab'][data-value]");
      if (!tab || !tabs.includes(tab)) return;
      const current = tabs.indexOf(tab);
      let next;
      if (event.key === "ArrowLeft")
        next = (current - 1 + tabs.length) % tabs.length;
      if (event.key === "ArrowRight") next = (current + 1) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next === undefined) return;
      event.preventDefault();
      tabs[next].focus();
      if (tabs[next] !== tab) tabs[next].click();
    });
    new MutationObserver(sync).observe(root, {
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-pressed"],
    });
    sync();
  }

  window.addEventListener("plan:page", (event) => {
    event.detail.element
      .querySelectorAll(".choice-tabs[data-choice]")
      .forEach(initialize);
  });
})();
