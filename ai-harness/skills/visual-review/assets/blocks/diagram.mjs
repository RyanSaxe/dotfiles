/**
 * Diagram and before-and-after.
 *
 * Mermaid on the frame's tokens, so a diagram belongs to whichever theme the
 * reader is in. A node whose label names a real location becomes a chip
 * inside the node, so a picture of the code opens the code.
 */
import { parseLocation } from "../grammar.mjs";
import {
  color,
  failed,
  libraries,
  module_,
  whenVisible,
} from "../libraries.mjs";
import { figure } from "./figure.mjs";

let sequence = Promise.resolve();

function themeVariables() {
  return {
    primaryColor: color("--panel"),
    primaryTextColor: color("--ink"),
    primaryBorderColor: color("--line-strong"),
    lineColor: color("--muted"),
    secondaryColor: color("--accent-soft"),
    tertiaryColor: color("--ground"),
    fontFamily: color("--sans") || "sans-serif",
  };
}

/** Mermaid renders one diagram at a time; its ids and fonts are global. */
export async function drawDiagram(element, source) {
  sequence = sequence
    .catch(() => {})
    .then(async () => {
      if (!element.isConnected) return;
      const { default: mermaid } = await module_(libraries.mermaid);
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        themeVariables: themeVariables(),
      });
      const { svg } = await mermaid.render(
        "vr-diagram-" + crypto.randomUUID(),
        source,
      );
      if (element.isConnected) element.innerHTML = svg;
    })
    .catch((error) => failed(element, error));
  return sequence;
}

/**
 * Turn node labels that name a location into chips the keyboard can reach.
 * Mermaid has already drawn the node, so this rewrites its text in place.
 */
function linkNodes(element, context) {
  for (const node of element.querySelectorAll(".node")) {
    const label = node.textContent.trim();
    const location = parseLocation(label);
    if (!location || !location.path.includes("/")) continue;
    node.classList.add("has-location");
    node.dataset.target = "diagram-node";
    node.dataset.location = label;
    node.style.cursor = "pointer";
    node.addEventListener("click", () => context.open(label));
  }
}

export function diagram(mount, data, context) {
  const { body } = figure(mount, { kind: "Diagram" });
  body.classList.add("diagram");
  const draw = async () => {
    await drawDiagram(body, data.source);
    linkNodes(body, context);
  };
  const stop = whenVisible(mount, draw);
  window.addEventListener("vr:theme", draw);
  return {
    dispose() {
      stop();
      window.removeEventListener("vr:theme", draw);
    },
  };
}

/**
 * The two mermaid blocks inside a `::: compare` container become one pair
 * with a legend. The container is already in the page; this claims the two
 * mounts inside it rather than rendering them separately.
 */
export function pairCompares(root) {
  for (const container of root.querySelectorAll(".compare")) {
    const mounts = [
      ...container.querySelectorAll("[data-block-name='mermaid']"),
    ];
    if (mounts.length !== 2) continue;
    for (const [index, mount] of mounts.entries()) {
      const side = document.createElement("div");
      side.className = "compare-side";
      const caption = document.createElement("h4");
      caption.textContent =
        index === 0 ? container.dataset.before : container.dataset.after;
      side.append(caption);
      mount.replaceWith(side);
      side.append(mount);
    }
    const legend = document.createElement("p");
    legend.className = "compare-legend";
    for (const name of ["added", "removed", "changed"]) {
      const key = document.createElement("span");
      key.className = `legend-key ${name}`;
      key.textContent = name;
      legend.append(key);
    }
    container.append(legend);
  }
}
