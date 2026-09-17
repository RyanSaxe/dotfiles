/**
 * Every external library the page uses, pinned in one place.
 *
 * Integrity is given where the CDN serves a single file. An ESM graph like
 * Pierre or markdown-it pulls further modules the page cannot hash ahead of
 * time, which is the same limit interactive-plan works under.
 */
export const libraries = {
  pierre: "https://esm.sh/@pierre/diffs@1.4.2?bundle",
  markdownIt: "https://esm.sh/markdown-it@15.0.2",
  container: "https://esm.sh/markdown-it-container@4.0.0",
  purify: "https://esm.sh/dompurify@3.4.15",
  mermaid:
    "https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.esm.min.mjs",
  katex: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js",
  katexCss: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css",
  echarts: "https://cdn.jsdelivr.net/npm/echarts@6.0.0/dist/echarts.min.js",
};

export const integrity = {
  [libraries.katex]:
    "sha384-cMkvdD8LoxVzGF/RPUKAcvmm49FQ0oxwDF3BGKtDXcEc+T1b2N+teh/OJfpU0jr6",
  [libraries.katexCss]:
    "sha384-5TcZemv2l/9On385z///+d7MSYlvIEw9FuZTIdZ14vJLqWphw7e7ZPuOiCHJcFCP",
  [libraries.echarts]:
    "sha384-F07Cpw5v8spSU0H113F33m2NQQ/o6GqPTnTjf45ssG4Q6q58ZwhxBiQtIaqvnSpR",
};

const loaded = new Map();

/** Load a classic script or stylesheet once, with its integrity hash. */
export function script(url, { css = false } = {}) {
  if (loaded.has(url)) return loaded.get(url);
  const task = new Promise((resolve, reject) => {
    const element = document.createElement(css ? "link" : "script");
    if (css) {
      element.rel = "stylesheet";
      element.href = url;
    } else element.src = url;
    if (integrity[url]) element.integrity = integrity[url];
    element.crossOrigin = "anonymous";
    element.onload = resolve;
    element.onerror = () =>
      reject(Error("Renderer unavailable; source preserved."));
    document.head.append(element);
  });
  loaded.set(url, task);
  return task;
}

const modules = new Map();

/** Import an ESM library once. */
export function module_(url) {
  if (!modules.has(url)) modules.set(url, import(/* @vite-ignore */ url));
  return modules.get(url);
}

/** A theme token's current value, for libraries that take colors as strings. */
export const color = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();

export const themeName = () =>
  document.documentElement.dataset.theme === "dark" ? "dark" : "light";

/** Show the reason beside a block whose renderer could not run. */
export function failed(element, error) {
  if (element.querySelector(".renderer-error")) return;
  const note = document.createElement("p");
  note.className = "renderer-error";
  note.textContent =
    error?.message || "Renderer unavailable; source preserved.";
  element.append(note);
}

const VIEWPORT_MARGIN = 300;

/**
 * Render a block once it is on screen, so a page costs the visuals the reader
 * can see rather than all of them.
 *
 * The geometric check is not redundant with the observer: an occluded or
 * backgrounded tab can report nothing through IntersectionObserver, and a
 * block that stays blank is worse than one drawn slightly early.
 */
export function whenVisible(element, render) {
  let done = false;
  const run = () => {
    if (done) return;
    done = true;
    observer.disconnect();
    render();
  };
  const observer = new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) run();
  });
  observer.observe(element);
  requestAnimationFrame(() => {
    if (done || !element.isConnected) return;
    const box = element.getBoundingClientRect();
    const height = window.innerHeight || 0;
    if (box.top < height + VIEWPORT_MARGIN && box.bottom > -VIEWPORT_MARGIN)
      run();
  });
  return () => observer.disconnect();
}
