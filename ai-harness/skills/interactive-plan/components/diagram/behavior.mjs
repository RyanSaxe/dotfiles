/* A Mermaid diagram, and the dialog that shows it full size. */
let mermaidTask;
let diagramSequence = Promise.resolve();
/* Mermaid keeps one global configuration and one id counter, so diagrams
   render one after another on a single chain rather than in parallel. */
function renderDiagram(element) {
  element.dataset.source ||= element.textContent;
  diagramSequence = diagramSequence
    .catch(() => {})
    .then(async () => {
      try {
        if (!element.isConnected) return;
        mermaidTask ||= import(libraries.mermaid);
        const { default: mermaid } = await mermaidTask;
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: "strict",
          theme: "base",
          themeVariables: {
            primaryColor: color("--ground"),
            primaryTextColor: color("--ink"),
            primaryBorderColor: color("--line-strong"),
            lineColor: color("--muted"),
            fontFamily: "sans-serif",
          },
          flowchart: {
            nodeSpacing: 28,
            rankSpacing: 36,
            padding: 12,
            subGraphTitleMargin: { top: 8, bottom: 8 },
          },
        });
        const result = await mermaid.render(
          "diagram-" + uuid(),
          element.dataset.source,
        );
        if (!element.isConnected) return;
        element.innerHTML = result.svg;
        const width = element.querySelector("svg")?.viewBox?.baseVal?.width;
        if (width) element.style.setProperty("--diagram-width", `${width}px`);
      } catch (error) {
        failed(element, error);
      }
    });
  return diagramSequence;
}
function renderDiagrams(root) {
  for (const element of root.querySelectorAll("[data-diagram]"))
    renderDiagram(element);
  return diagramSequence;
}
// Any rendered diagram opens full size; the dialog closes on Escape or a
// click outside like the other dialogs.
$("page-content").addEventListener("click", (event) => {
  const svg = event.target.closest("[data-diagram] svg");
  if (!svg || event.target.closest("a")) return;
  const clone = svg.cloneNode(true);
  clone.style.width = `${svg.viewBox.baseVal.width}px`;
  clone.removeAttribute("width");
  $("diagram-dialog").replaceChildren(clone);
  $("diagram-dialog").showModal();
});
/* Mermaid bakes the theme into the SVG it writes, so a theme change
   draws every diagram on the page again. */
window.addEventListener("plan:theme", () =>
  renderDiagrams(document.getElementById("page-content")),
);
planUI.define("diagram", {
  match: "[data-diagram]",
  setup(element) {
    if (element.dataset.caption)
      figure(element, { caption: element.dataset.caption, kind: "diagram" });
    return renderDiagram(element);
  },
});
