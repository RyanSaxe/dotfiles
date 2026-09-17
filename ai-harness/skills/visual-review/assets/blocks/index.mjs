/**
 * Block components mount here.
 *
 * The renderer leaves one element per fenced block and knows nothing about how
 * any of them look. This module owns that mapping. A block with no component,
 * or one whose data the grammar could not read, shows its source with the
 * reason, so an explanation never has a silent gap where a visual should be.
 */
import { chart } from "./chart.mjs";
import { choice } from "./choice.mjs";
import { diagram, pairCompares } from "./diagram.mjs";
import { diff } from "./diff.mjs";
import { excerpt } from "./excerpt.mjs";
import { renderMath } from "./math.mjs";
import { steps } from "./steps.mjs";

const components = new Map([
  ["mermaid", diagram],
  ["code", excerpt],
  ["diff", diff],
  ["steps", steps],
  ["choose", choice],
  ["chart", chart],
]);

export function renderBlock(mount, block, context) {
  if (!block) return;
  const component = components.get(block.name);
  if (!component) return showSource(mount, block);
  try {
    const instance = component(mount, block.data, context);
    if (instance) mount.__block = instance;
  } catch (error) {
    showSource(mount, block, error.message);
  }
}

/** Everything a page needs beyond its individual blocks. */
export async function renderPageExtras(root, context) {
  pairCompares(root, context);
  await renderMath(root);
}

export function disposeBlocks(root) {
  for (const mount of root.querySelectorAll("[data-block]"))
    mount.__block?.dispose?.();
}

/** The block the reader is on, for the keys that act on one. */
export function blockInstance(element) {
  return element?.closest("[data-block]")?.__block ?? null;
}

function showSource(mount, block, reason) {
  mount.classList.add("block-source");
  const pre = document.createElement("pre");
  const code = document.createElement("code");
  code.textContent =
    "```" +
    [block.name, block.argument].filter(Boolean).join(" ") +
    "\n" +
    block.source +
    "```";
  pre.append(code);
  mount.replaceChildren(pre);
  const message = reason ?? block.error;
  if (!message) return;
  const note = document.createElement("p");
  note.className = "renderer-error";
  note.textContent = message;
  mount.append(note);
}
