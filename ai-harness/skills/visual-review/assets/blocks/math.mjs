/** TeX between dollar signs, rendered by KaTeX where the agent wrote it. */
import { failed, libraries, script } from "../libraries.mjs";

export async function renderMath(root) {
  const targets = [...root.querySelectorAll("[data-math]")];
  if (!targets.length) return;
  try {
    await Promise.all([
      script(libraries.katex),
      script(libraries.katexCss, { css: true }),
    ]);
  } catch (error) {
    for (const element of targets)
      failed(element.parentElement ?? element, error);
    return;
  }
  for (const element of targets) {
    if (!element.isConnected) continue;
    try {
      window.katex.render(element.textContent, element, {
        throwOnError: true,
        displayMode: element.dataset.math === "block",
      });
    } catch (error) {
      failed(element.parentElement ?? element, error);
    }
  }
}
