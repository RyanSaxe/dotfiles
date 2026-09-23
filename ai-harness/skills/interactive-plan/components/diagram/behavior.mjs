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
      /* Mermaid renders into a container of its own named after the render
         id. It removes that container when the render succeeds and leaves it
         attached to the body when the source does not parse, where it draws
         a full-width error graphic outside the app. */
      const id = "diagram-" + uuid();
      try {
        if (!element.isConnected) return;
        mermaidTask ||= (async () => {
          const [{ default: mermaid }, elk] = await Promise.all([
            import(libraries.mermaid),
            import(libraries.elk),
          ]);
          mermaid.registerLayoutLoaders(elk.default ?? elk);
          return mermaid;
        })();
        const mermaid = await mermaidTask;
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: "strict",
          theme: "base",
          themeVariables: {
            primaryColor: color("--panel"),
            primaryTextColor: color("--ink"),
            primaryBorderColor: color("--line-strong"),
            lineColor: color("--muted"),
            secondaryColor: color("--panel"),
            tertiaryColor: color("--ground"),
            clusterBkg: "transparent",
            clusterBorder: color("--line"),
            fontFamily: "ui-sans-serif, system-ui, sans-serif",
          },
          layout: "elk",
          flowchart: {
            nodeSpacing: 28,
            rankSpacing: 38,
            titleTopMargin: 8,
            htmlLabels: true,
          },
        });
        const result = await mermaid.render(id, element.dataset.source);
        if (!element.isConnected) return;
        element.innerHTML = result.svg;
        const width = element.querySelector("svg")?.viewBox?.baseVal?.width;
        if (width) element.style.setProperty("--diagram-width", `${width}px`);
        linkNodes(element);
      } catch (error) {
        failed(element, error);
      } finally {
        document.getElementById("d" + id)?.remove();
      }
    });
  return diagramSequence;
}
function linkNodes(element) {
  for (const node of element.querySelectorAll(".node")) {
    const id = node.id.match(/^flowchart-(.+)-\d+$/)?.[1];
    if (!id || !pages.some((item) => item.id === id)) continue;
    node.classList.add("linked");
    node.setAttribute("role", "link");
    node.tabIndex = 0;
    node.setAttribute(
      "aria-label",
      `Open ${pages.find((item) => item.id === id).title}`,
    );
    const open = (event) => {
      event?.stopPropagation();
      show(id);
    };
    node.addEventListener("click", open);
    node.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        open(event);
      }
    });
  }
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
  if (!svg || event.target.closest("a, .node.linked")) return;
  openLightbox(svg);
});
function openLightbox(svg) {
  const dialog = $("diagram-dialog");
  dialog.style.setProperty(
    "--diagram-width",
    svg.closest("[data-diagram]").style.getPropertyValue("--diagram-width"),
  );
  const clone = svg.cloneNode(true);
  for (const node of clone.querySelectorAll(".node.linked")) {
    node.removeAttribute("tabindex");
    node.removeAttribute("role");
  }
  dialog.replaceChildren(clone);
  dialog.onclick = (event) => {
    const id = event.target
      .closest(".node.linked")
      ?.id.match(/^flowchart-(.+)-\d+$/)?.[1];
    if (!id) return;
    dialog.close();
    show(id);
  };
  dialog.showModal();
}
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
