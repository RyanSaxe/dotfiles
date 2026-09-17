/**
 * Block components mount here.
 *
 * The renderer leaves one element per fenced block and knows nothing about how
 * any of them look. This module owns that mapping. A block with no component
 * yet shows its source, which is also what an unreadable block does, so an
 * explanation never has a silent gap where a visual should be.
 */
const components = new Map();

export function register(name, component) {
  components.set(name, component);
}

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

export function disposeBlocks(root) {
  for (const mount of root.querySelectorAll("[data-block]"))
    mount.__block?.dispose?.();
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
