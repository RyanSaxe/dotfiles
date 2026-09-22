/* A chart. planUI.chart owns the renderer and the theme; this reads the
   options out of the page and gives the figure its chrome. */
planUI.define("chart", {
  match: "[data-chart]",
  setup(element, { planUI }) {
    const options = JSON.parse(element.textContent);
    element.textContent = "";
    if (element.dataset.title || element.dataset.caption)
      figure(element, {
        title: element.dataset.title,
        caption: element.dataset.caption,
        kind: "chart",
      });
    return planUI.chart(element, options).catch((error) => {
      element.textContent = JSON.stringify(options, null, 2);
      failed(element, error);
    });
  },
});
