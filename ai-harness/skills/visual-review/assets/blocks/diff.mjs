/**
 * Diff: one file between two refs, or against a pull request head.
 *
 * Pierre's diff view, split or unified, with notes as markers in the gutter of
 * the side they belong to.
 */
import { targetKey } from "../grammar.mjs";
import { failed, themeName, whenVisible } from "../libraries.mjs";
import { loadPierre } from "../code.mjs";
import { createMarkers } from "../notes.mjs";
import { request } from "../transport.mjs";
import { figure } from "./figure.mjs";

export function diff(mount, data, context) {
  let style = "split";
  let view = null;
  let markers = null;

  const toggle = document.createElement("div");
  toggle.className = "figure-toggle";
  for (const [value, label] of [
    ["split", "Side by side"],
    ["unified", "Unified"],
  ]) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.setAttribute("aria-pressed", String(value === style));
    button.onclick = () => {
      style = value;
      for (const other of toggle.children)
        other.setAttribute("aria-pressed", String(other === button));
      view?.setOptions({ ...view.options, diffStyle: style });
      view?.rerender();
    };
    toggle.append(button);
  }
  const { body } = figure(mount, {
    name: data.path,
    detail: `${data.base} → ${data.head}`,
    action: toggle,
    caption: data.prose,
  });
  body.classList.add("diff-body");
  // The page cursor can land on the diff, so . and , reach its markers.
  mount.dataset.target = "diff";

  const notes = context.registry.forTarget(
    targetKey({
      kind: "diff",
      base: data.base,
      head: data.head,
      path: data.path,
    }),
  );

  const stop = whenVisible(mount, async () => {
    try {
      const query = new URLSearchParams({
        base: data.base,
        head: data.head,
        path: data.path,
      });
      const response = await request(`/repo/diff?${query}`);
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      if (!result.patch.trim()) {
        body.textContent = "No changes to this file between these refs.";
        body.classList.add("placeholder");
        return;
      }
      const { FileDiff, parsePatchFiles } = await loadPierre();
      const files = parsePatchFiles(result.patch).flatMap(
        (patch) => patch.files,
      );
      if (files.length !== 1) throw new Error("A diff block shows one file");
      view = new FileDiff({
        theme: { light: "github-light", dark: "github-dark" },
        themeType: themeName(),
        // The figure head carries the path, the refs, and the split control.
        disableFileHeader: true,
        diffStyle: style,
        lineDiffType: "word-alt",
        diffIndicators: "classic",
        overflow: "wrap",
        renderAnnotation: (annotation) => markers.renderAnnotation(annotation),
        onPostRender: () => markers.inject(),
      });
      markers = createMarkers({
        view,
        container: body,
        notes,
        navigate: context.navigate,
      });
      view.render({
        fileDiff: files[0],
        containerWrapper: body,
        lineAnnotations: [],
      });
    } catch (error) {
      failed(mount, error);
    }
  });

  const retheme = () => {
    view?.setThemeType(themeName() === "dark" ? "dark" : "light");
    markers?.inject();
  };
  window.addEventListener("vr:theme", retheme);

  return {
    step: (delta) => markers?.step(delta),
    dispose() {
      stop();
      window.removeEventListener("vr:theme", retheme);
      view?.cleanUp();
    },
  };
}
