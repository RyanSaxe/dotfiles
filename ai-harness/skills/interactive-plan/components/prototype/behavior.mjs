/* An approved prototype in a sandboxed frame, with its source beneath. */
function prototypeUrl(prototype) {
  if (online)
    return `${base}/r/${encodeURIComponent(plan.revision)}/prototype/${encodeURIComponent(prototype.id)}`;
  return URL.createObjectURL(new Blob([prototype.html], { type: "text/html" }));
}
planUI.define("prototype", {
  match: "[data-prototype]",
  setup(mount, { planUI }) {
    const prototype = plan.prototypes?.find(
      (item) => item.id === mount.dataset.prototype,
    );
    if (!prototype) throw Error("Prototype unavailable.");
    const frame = document.createElement("iframe");
    frame.title = prototype.title;
    frame.className = "approved-prototype";
    frame.setAttribute("sandbox", "allow-scripts allow-forms allow-popups");
    frame.setAttribute("allowtransparency", "true");
    frame.style.height = `${prototype.height}px`;
    frame.srcdoc = prototype.html;
    const details = document.createElement("details");
    details.className = "prototype-source";
    const summary = document.createElement("summary");
    summary.textContent = "Source HTML, CSS, and JavaScript";
    details.append(summary);
    details.addEventListener("toggle", () => {
      if (!details.open || details.querySelector("[data-language]")) return;
      const source = document.createElement("div");
      source.dataset.language = "html";
      source.textContent = prototype.html;
      details.append(source);
      planUI.enhance(details);
    });
    const open = document.createElement("a");
    open.textContent = "Open full size";
    open.target = "_blank";
    open.rel = "noopener";
    open.href = online ? prototypeUrl(prototype) : "#";
    if (!online)
      open.onclick = (event) => {
        event.preventDefault();
        window.open(prototypeUrl(prototype), "_blank", "noopener");
      };
    const source = linkButton("Source", () => {
      details.open = !details.open;
    });
    mount.append(frame);
    const wrapper = figure(mount, {
      title: prototype.title,
      actions: [source, document.createTextNode("·"), open],
      kind: "prototype",
    });
    wrapper.append(details);
  },
});
