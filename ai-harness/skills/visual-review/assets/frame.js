const $ = (id) => document.getElementById(id);
const doc = JSON.parse($("document-data").textContent);
const pages = doc.pages;
const pageIds = new Set(pages.map((item) => item.id));

/* Theme */
const systemTheme = matchMedia("(prefers-color-scheme: dark)");
let preferredTheme = null;
try {
  if (/^https?:$/.test(location.protocol)) {
    const value = document.cookie
      .split("; ")
      .find((item) => item.startsWith("visual-review-theme="))
      ?.split("=")[1];
    if (["light", "dark"].includes(value)) preferredTheme = value;
  }
} catch {
  /* Theme changes remain available without storage. */
}
let activeTheme = preferredTheme || (systemTheme.matches ? "dark" : "light");
const syntaxThemes = { light: "github-light", dark: "github-dark" };
const color = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();

/* Renderers and figures */
const libraries = {
  shiki: "https://esm.sh/shiki@3.12.2",
  diffs: "https://esm.sh/@pierre/diffs@1.4.2?bundle",
  mermaid:
    "https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.esm.min.mjs",
  elk: "https://cdn.jsdelivr.net/npm/@mermaid-js/layout-elk@0.2.3/dist/mermaid-layout-elk.esm.min.mjs",
  katex: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js",
  katexCss: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css",
  echarts: "https://cdn.jsdelivr.net/npm/echarts@6.0.0/dist/echarts.min.js",
};
const scripts = new Map();
const charts = new Map();
const diffs = new Map();
let shikiTask, diffsTask, mermaidTask;
let diagramSequence = Promise.resolve();

function script(url, integrity, css = false) {
  if (scripts.has(url)) return scripts.get(url);
  const task = new Promise((resolve, reject) => {
    const element = document.createElement(css ? "link" : "script");
    if (css) {
      element.rel = "stylesheet";
      element.href = url;
    } else element.src = url;
    element.integrity = integrity;
    element.crossOrigin = "anonymous";
    element.onload = resolve;
    element.onerror = () =>
      reject(Error("Renderer unavailable; source preserved."));
    document.head.append(element);
  });
  scripts.set(url, task);
  return task;
}
function failed(element, error) {
  if (
    !element.isConnected ||
    element.nextElementSibling?.classList.contains("renderer-error")
  )
    return;
  const note = document.createElement("p");
  note.className = "renderer-error";
  note.textContent = error.message || "Renderer unavailable; source preserved.";
  element.after(note);
}
function figure(element, { title, meta, actions = [], caption, kind = "" }) {
  if (element.parentElement?.classList.contains("figure-body"))
    return element.parentElement.parentElement;
  const wrapper = document.createElement("figure");
  wrapper.className = `figure ${kind}`.trim();
  if (title || meta || actions.length) {
    const head = document.createElement("figcaption");
    head.className = "figure-head";
    const name = document.createElement("b");
    name.textContent = title || "";
    const side = document.createElement("span");
    if (meta) side.append(meta);
    side.append(...actions);
    head.append(name, side);
    wrapper.append(head);
  }
  const body = document.createElement("div");
  body.className = "figure-body";
  element.replaceWith(wrapper);
  body.append(element);
  wrapper.append(body);
  if (caption) {
    const line = document.createElement("div");
    line.className = "figure-caption";
    line.textContent = caption;
    wrapper.append(line);
  }
  return wrapper;
}
function copyButton(read) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "btn";
  button.textContent = "Copy";
  button.onclick = async () => {
    try {
      await navigator.clipboard.writeText(read());
      button.textContent = "Copied";
    } catch {
      button.textContent = "Copy failed";
    }
    setTimeout(() => (button.textContent = "Copy"), 1500);
  };
  return button;
}
async function highlighted(source, lang) {
  shikiTask ||= import(libraries.shiki);
  const { codeToHtml } = await shikiTask;
  return codeToHtml(source, {
    lang,
    themes: syntaxThemes,
    defaultColor: false,
  });
}
async function renderCode(element) {
  const source = element.textContent;
  try {
    const html = await highlighted(source, element.dataset.language);
    if (element.isConnected) element.innerHTML = html;
  } catch (error) {
    failed(element, error);
  }
}

/* Diagrams: Mermaid laid out by ELK, painted by the stylesheet. */
async function loadMermaid() {
  mermaidTask ||= (async () => {
    const [{ default: mermaid }, elk] = await Promise.all([
      import(libraries.mermaid),
      import(libraries.elk),
    ]);
    // mermaid 11.12.0 accepts layout: "elk" and silently keeps its own
    // layout unless the loaders are registered.
    mermaid.registerLayoutLoaders(elk.default ?? elk);
    return mermaid;
  })();
  return mermaidTask;
}
function linkNodes(element) {
  for (const node of element.querySelectorAll(".node")) {
    const id = node.id.match(/^flowchart-(.+)-\d+$/)?.[1];
    if (!id || !pageIds.has(id)) continue;
    node.classList.add("linked");
    node.setAttribute("role", "link");
    node.tabIndex = 0;
    const open = () => show(id);
    node.addEventListener("click", open);
    node.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        open();
      }
    });
  }
}
function renderDiagrams(root) {
  for (const element of root.querySelectorAll("[data-diagram]")) {
    element.dataset.source ||= element.textContent;
    diagramSequence = diagramSequence
      .catch(() => {})
      .then(async () => {
        try {
          if (!element.isConnected) return;
          const mermaid = await loadMermaid();
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
              rankSpacing: 38,
              nodeSpacing: 28,
              titleTopMargin: 8,
              htmlLabels: true,
            },
          });
          const result = await mermaid.render(
            "diagram-" + crypto.randomUUID(),
            element.dataset.source,
          );
          if (!element.isConnected) return;
          element.innerHTML = result.svg;
          const width = element.querySelector("svg")?.viewBox?.baseVal?.width;
          if (width) element.style.setProperty("--diagram-width", `${width}px`);
          linkNodes(element);
        } catch (error) {
          failed(element, error);
        }
      });
  }
}
function openLightbox(svg) {
  const dialog = $("diagram-dialog");
  // The clone is drawn at the size the page drew it; the box hugs it.
  dialog.style.setProperty(
    "--diagram-width",
    svg.closest("[data-diagram]").style.getPropertyValue("--diagram-width"),
  );
  const clone = svg.cloneNode(true);
  // A linked node still opens its page from here, through the dialog rather
  // than through focus: showModal would otherwise land on the first node and
  // ring it for no reason.
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

/* Mathematics */
function wireSymbols(element) {
  for (const symbol of element.querySelectorAll("[data-lines]")) {
    const lines = new Set(
      symbol.dataset.lines
        .split(/[\s,]+/)
        .map(Number)
        .filter(Number.isFinite),
    );
    symbol.tabIndex = 0;
    symbol.setAttribute("role", "button");
    // A symbol lights its rows in the accent, apart from the amber a note
    // gives a span, so a press always shows even on an annotated line.
    const toggle = () => {
      const on = !symbol.classList.contains("on");
      for (const other of $("page-content").querySelectorAll("[data-lines].on"))
        other.classList.remove("on");
      for (const row of $("page-content").querySelectorAll(
        ".excerpt-code .row.sym",
      ))
        row.classList.remove("sym");
      if (!on) return;
      symbol.classList.add("on");
      for (const row of $("page-content").querySelectorAll(
        ".excerpt-code .row",
      ))
        if (lines.has(Number(row.dataset.line))) row.classList.add("sym");
    };
    symbol.addEventListener("click", toggle);
    symbol.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        toggle();
      }
    });
  }
}
async function renderMath(element) {
  try {
    await Promise.all([
      script(
        libraries.katex,
        "sha384-cMkvdD8LoxVzGF/RPUKAcvmm49FQ0oxwDF3BGKtDXcEc+T1b2N+teh/OJfpU0jr6",
      ),
      script(
        libraries.katexCss,
        "sha384-5TcZemv2l/9On385z///+d7MSYlvIEw9FuZTIdZ14vJLqWphw7e7ZPuOiCHJcFCP",
        true,
      ),
    ]);
    if (!element.isConnected) return;
    element.dataset.source ||= element.textContent;
    // trust lets \htmlData put an identity on a symbol, which is how a
    // symbol finds the lines that compute it.
    window.katex.render(element.dataset.source, element, {
      throwOnError: true,
      displayMode: element.dataset.math !== "inline",
      trust: true,
      strict: false,
    });
    wireSymbols(element);
  } catch (error) {
    failed(element, error);
  }
}

/* Charts */
// Series take the tokens in this order; a chart with one series is the accent.
const chartPalette = () =>
  ["--accent", "--mark", "--add", "--cut", "--muted"].map(color);
function chartTheme(options) {
  const result = {
    backgroundColor: "transparent",
    textStyle: { color: color("--ink") },
    tooltip: {
      backgroundColor: color("--panel"),
      borderColor: color("--line"),
      textStyle: { color: color("--ink") },
    },
  };
  for (const key of ["xAxis", "yAxis"]) {
    if (!options[key]) continue;
    const axes = Array.isArray(options[key]) ? options[key] : [options[key]];
    result[key] = axes.map(() => ({
      axisLabel: { color: color("--muted") },
      axisLine: { lineStyle: { color: color("--line") } },
      splitLine: { lineStyle: { color: color("--line") } },
    }));
  }
  return result;
}
async function chart(element, options) {
  await script(
    libraries.echarts,
    "sha384-F07Cpw5v8spSU0H113F33m2NQQ/o6GqPTnTjf45ssG4Q6q58ZwhxBiQtIaqvnSpR",
  );
  if (!element.isConnected) return null;
  let instance = charts.get(element);
  if (!instance) {
    instance = window.echarts.init(element, null, { renderer: "svg" });
    charts.set(element, instance);
  }
  instance.setOption(
    {
      backgroundColor: "transparent",
      color: chartPalette(),
      textStyle: { color: color("--ink") },
      ...options,
    },
    true,
  );
  instance.setOption(chartTheme(options));
  return instance;
}

/* Diffs: the Pierre viewer, the one way a change is shown. */
async function diff(element, input, { diffStyle = "split" } = {}) {
  if (typeof input.patch !== "string") throw Error("A Git patch is required.");
  if (!input.patch) {
    element.textContent = "No changes.";
    return null;
  }
  diffsTask ||= import(libraries.diffs);
  const { FileDiff, parsePatchFiles } = await diffsTask;
  if (!element.isConnected) return null;
  let viewer = diffs.get(element);
  if (viewer) {
    viewer.setOptions({ ...viewer.options, diffStyle });
    viewer.rerender();
    return viewer;
  }
  const files = parsePatchFiles(input.patch).flatMap((patch) => patch.files);
  if (files.length !== 1) throw Error("A change shows one file.");
  viewer = new FileDiff({
    theme: syntaxThemes[activeTheme],
    diffStyle,
    lineDiffType: "word-alt",
    diffIndicators: "classic",
    overflow: "wrap",
    disableFileHeader: true,
  });
  element.replaceChildren();
  viewer.render({ fileDiff: files[0], containerWrapper: element });
  diffs.set(element, viewer);
  return viewer;
}
function renderChange(root) {
  const input = root.querySelector("[data-diff-input]");
  const view = root.querySelector(".change-view");
  if (!input || !view || root.dataset.ready) return;
  root.dataset.ready = "true";
  let parsed;
  try {
    parsed = JSON.parse(input.value || input.textContent);
  } catch (error) {
    failed(view, Error("The change's input is not JSON."));
    return;
  }
  const head = document.createElement("figcaption");
  head.className = "figure-head";
  const name = document.createElement("b");
  name.textContent = root.dataset.file || "";
  const side = document.createElement("span");
  const toggle = document.createElement("span");
  toggle.setAttribute("role", "group");
  toggle.setAttribute("aria-label", "Diff layout");
  let diffStyle = window.innerWidth >= 900 ? "split" : "unified";
  const buttons = [];
  for (const [value, label] of [
    ["split", "Side by side"],
    ["unified", "Unified"],
  ]) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn";
    button.dataset.diffStyle = value;
    button.textContent = label;
    button.setAttribute("aria-pressed", String(value === diffStyle));
    button.onclick = () => {
      diffStyle = value;
      for (const other of buttons)
        other.setAttribute("aria-pressed", String(other === button));
      diff(view, parsed, { diffStyle }).catch((error) => failed(view, error));
    };
    buttons.push(button);
    toggle.append(button);
  }
  side.append(toggle);
  head.append(name, side);
  root.prepend(head);
  diff(view, parsed, { diffStyle }).catch((error) => failed(view, error));
}

/* The annotated code block: rows the build read, notes the agent wrote. */
async function renderExcerpt(root) {
  if (root.dataset.ready) return;
  root.dataset.ready = "true";
  const code = root.querySelector(".excerpt-code");
  if (!code) {
    failed(root, Error("The excerpt has no lines; was the document built?"));
    return;
  }
  const head = document.createElement("figcaption");
  head.className = "figure-head";
  const name = document.createElement("b");
  name.textContent = root.dataset.file || "";
  const meta = document.createElement("span");
  meta.textContent = `lines ${root.dataset.lines} · ${root.dataset.language}`;
  head.append(name, meta);
  root.prepend(head);
  const rows = new Map();
  for (const row of code.querySelectorAll(".row"))
    rows.set(Number(row.dataset.line), row);
  for (const note of root.querySelectorAll(":scope > .notes > li")) {
    const row = rows.get(Number(note.dataset.line));
    const span = note.dataset.span?.match(/^(\d+)-(\d+)$/);
    if (span)
      for (let n = Number(span[1]); n <= Number(span[2]); n += 1)
        rows.get(n)?.classList.add("lit");
    const inline = document.createElement("p");
    inline.className = "note-inline";
    inline.append(...note.childNodes);
    if (row) row.after(inline);
    else code.append(inline);
  }
  const targets = [...code.querySelectorAll(".src")];
  try {
    const html = await highlighted(
      targets.map((target) => target.textContent).join("\n"),
      code.dataset.lang,
    );
    const parsed = new DOMParser().parseFromString(html, "text/html");
    const lines = [...parsed.querySelectorAll("pre code .line")];
    lines.forEach((line, index) => {
      if (targets[index]) targets[index].innerHTML = line.innerHTML;
    });
  } catch {
    /* The lines still read. */
  }
}

/* A figure a reader can move. */
function renderControls(root) {
  if (root.dataset.ready) return;
  root.dataset.ready = "true";
  const body = root.querySelector("script[data-script]")?.textContent;
  if (!body) return;
  const inputs = [...root.querySelectorAll("[data-control]")];
  const draw = {
    chart: (options) => {
      const target = root.querySelector("[data-chart]");
      if (!target)
        throw Error("draw.chart needs a [data-chart] in the figure.");
      return chart(target, options);
    },
    text: (selector, text) => {
      const target = root.querySelector(selector);
      if (target) target.textContent = text;
    },
  };
  let run;
  try {
    run = new Function("figure", "controls", "draw", body);
  } catch (error) {
    failed(root, error);
    return;
  }
  const controls = () =>
    Object.fromEntries(
      inputs.map((input) => [
        input.dataset.control,
        input.type === "checkbox"
          ? input.checked
          : Number.isNaN(Number(input.value))
            ? input.value
            : Number(input.value),
      ]),
    );
  const render = () => {
    for (const input of inputs) {
      const output = input.parentElement?.querySelector("output");
      if (output) output.textContent = input.value;
    }
    try {
      const result = run(root, controls(), draw);
      if (result?.catch) result.catch((error) => failed(root, error));
    } catch (error) {
      failed(root, error);
    }
  };
  for (const input of inputs) input.addEventListener("input", render);
  render();
}

function enhance(root) {
  // An excerpt carries data-language for its rows; the figure itself is not
  // a code block and must not be rendered as one.
  root.querySelectorAll("[data-language]:not(.excerpt)").forEach((element) => {
    if (element.dataset.file !== undefined || element.dataset.caption) {
      const meta = document.createElement("span");
      meta.textContent = element.dataset.language;
      figure(element, {
        title: element.dataset.file,
        meta,
        actions: [
          copyButton(() => element.dataset.source ?? element.textContent),
        ],
        caption: element.dataset.caption,
        kind: "code",
      });
    }
    element.dataset.source ||= element.textContent;
    renderCode(element);
  });
  root.querySelectorAll("[data-math]").forEach(renderMath);
  root
    .querySelectorAll("[data-diagram][data-caption]")
    .forEach((element) =>
      figure(element, { caption: element.dataset.caption, kind: "diagram" }),
    );
  renderDiagrams(root);
  root.querySelectorAll("[data-chart]").forEach((element) => {
    if (element.closest("[data-figure]")) return;
    try {
      const options = JSON.parse(element.textContent);
      element.textContent = "";
      if (element.dataset.title || element.dataset.caption)
        figure(element, {
          title: element.dataset.title,
          caption: element.dataset.caption,
          kind: "chart",
        });
      chart(element, options).catch((error) => failed(element, error));
    } catch (error) {
      failed(element, error);
    }
  });
  root.querySelectorAll(".excerpt").forEach(renderExcerpt);
  root.querySelectorAll(".change").forEach(renderChange);
  root.querySelectorAll("[data-figure]").forEach(renderControls);
}
function disposeRenderers() {
  for (const instance of charts.values()) instance.dispose();
  charts.clear();
  for (const viewer of diffs.values()) viewer.cleanUp();
  diffs.clear();
}
new ResizeObserver(() => {
  for (const instance of charts.values()) instance.resize();
}).observe($("page-content"));

/* Pages */
let page = pages[0];
function renderRail() {
  const nav = $("navigation");
  nav.replaceChildren();
  for (const item of pages) {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.page = item.id;
    button.textContent = item.title;
    if (item.depth === 1) button.className = "sub";
    nav.append(button);
  }
}
function renderFooter() {
  const index = pages.indexOf(page);
  const previous = pages[index - 1];
  const next = pages[index + 1];
  $("footer-previous").hidden = !previous;
  $("footer-next").hidden = !next;
  if (previous) {
    $("footer-previous").textContent = `← ${previous.title}`;
    $("footer-previous").dataset.page = previous.id;
  }
  if (next) {
    $("footer-next").textContent = `${next.title} →`;
    $("footer-next").dataset.page = next.id;
  }
}
// Page changes push history so the back button and a pasted hash both work;
// restoring after a reload and popstate itself leave history alone.
function show(id, { push = true } = {}) {
  page = pages.find((item) => item.id === id) || pages[0];
  const first = page === pages[0];
  disposeRenderers();
  $("page-title").textContent = first ? doc.title : page.title;
  $("lede").hidden = !(first && doc.lede);
  $("lede").textContent = first && doc.lede ? doc.lede : "";
  $("opening").hidden = !(first && doc.opens);
  $("opening").replaceChildren();
  if (first && doc.opens) {
    const holder = document.createElement("div");
    holder.dataset.diagram = "";
    if (doc.opensCaption) holder.dataset.caption = doc.opensCaption;
    holder.textContent = doc.opens;
    $("opening").append(holder);
    enhance($("opening"));
  }
  $("page-content").innerHTML = page.html;
  enhance($("page-content"));
  for (const button of $("navigation").querySelectorAll("[data-page]")) {
    if (button.dataset.page === page.id)
      button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  }
  renderFooter();
  const url = new URL(location.href);
  url.hash = page.id;
  if (push && url.href !== location.href) history.pushState(null, "", url);
  else history.replaceState(null, "", url);
  $("page-title").focus({ preventScroll: true });
  window.scrollTo(0, 0);
  if ($("pages-menu").querySelector("summary").offsetParent)
    $("pages-menu").open = false;
}

/* Theme */
function theme() {
  document.documentElement.dataset.theme = activeTheme;
  $("theme").value = preferredTheme || "system";
  for (const instance of charts.values())
    instance.setOption({
      color: chartPalette(),
      ...chartTheme(instance.getOption()),
    });
  for (const viewer of diffs.values()) {
    viewer.setOptions({ ...viewer.options, theme: syntaxThemes[activeTheme] });
    viewer.rerender();
  }
  renderDiagrams($("opening"));
  renderDiagrams($("page-content"));
}
$("theme").onchange = () => {
  preferredTheme = $("theme").value === "system" ? null : $("theme").value;
  activeTheme = preferredTheme || (systemTheme.matches ? "dark" : "light");
  try {
    if (/^https?:$/.test(location.protocol))
      document.cookie = `visual-review-theme=${preferredTheme || ""}; Path=/; SameSite=Strict; Max-Age=${preferredTheme ? 31536000 : 0}`;
  } catch {
    /* Keep the explicit choice in memory when cookies are blocked. */
  }
  theme();
};
systemTheme.addEventListener("change", () => {
  if (preferredTheme) return;
  activeTheme = systemTheme.matches ? "dark" : "light";
  theme();
});

/* Clicks and keys */
document.addEventListener("click", (event) => {
  const close = event.target.closest("[data-close]");
  if (close) $(close.dataset.close).close();
  const navigation = event.target.closest("[data-page]");
  if (navigation) {
    event.preventDefault();
    show(navigation.dataset.page);
    return;
  }
  const svg = event.target.closest("[data-diagram] svg");
  if (svg && !event.target.closest(".node.linked")) openLightbox(svg);
});
for (const dialog of document.querySelectorAll("dialog")) {
  dialog.addEventListener("click", (event) => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (
      event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom
    )
      dialog.close();
  });
}
const interactiveSelector =
  "a[href], button, input, select, [data-lines], .node.linked, [data-diff-style], summary";
document.addEventListener("keydown", (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key === "Escape") {
    $("settings-menu").hidePopover?.();
    return;
  }
  if (event.target.closest("input, textarea, select, [contenteditable]"))
    return;
  if (document.querySelector("dialog[open]")) return;
  const key = event.key;
  if (key === "?") $("keys-dialog").showModal();
  else if (key === "]" || key === "[") {
    const index = pages.indexOf(page);
    const next = pages[index + (key === "]" ? 1 : -1)];
    if (next) show(next.id);
  } else if (key === "j" || key === "k") {
    const items = Array.from(
      $("content").querySelectorAll(interactiveSelector),
    ).filter((item) => item.offsetParent || item instanceof SVGElement);
    if (!items.length) return;
    const index = items.indexOf(document.activeElement);
    const next =
      items[
        index < 0
          ? key === "j"
            ? 0
            : items.length - 1
          : (index + (key === "j" ? 1 : -1) + items.length) % items.length
      ];
    next.focus({ preventScroll: true });
    next.scrollIntoView({ block: "center" });
  } else return;
  event.preventDefault();
});

/* Asking again: the file on disk is the whole state. Served over HTTP the
   page notices a rebuild and reloads; the page is in the hash, so the
   reload lands where the reader was. From the filesystem there is nothing
   to poll and the reader presses reload. */
if (/^https?:$/.test(location.protocol)) {
  let seen = null;
  setInterval(async () => {
    try {
      const response = await fetch(location.href, {
        method: "HEAD",
        cache: "no-store",
      });
      const stamp = response.headers.get("last-modified");
      if (seen && stamp && stamp !== seen) location.reload();
      seen = stamp || seen;
    } catch {
      /* Offline or served without dates: nothing to notice. */
    }
  }, 2000);
}

/* Start */
document.title = doc.title;
$("doc-title").textContent = doc.title;
$("doc-subtitle").textContent = doc.subtitle || "";
$("doc-subtitle").hidden = !doc.subtitle;
// The ref and the commit it resolved to, unless they say the same thing.
const short = (doc.commit || "").slice(0, 7);
$("doc-ref").textContent = !doc.commit
  ? ""
  : doc.ref === "HEAD" || doc.commit.startsWith(doc.ref)
    ? short
    : `${doc.ref} · ${short}`;
$("doc-ref").hidden = !doc.commit;
renderRail();
const narrow = matchMedia("(max-width: 720px)");
const layoutMenu = () => {
  $("pages-menu").open = !narrow.matches;
};
narrow.addEventListener("change", layoutMenu);
layoutMenu();
theme();
show(location.hash.slice(1) || pages[0].id, { push: false });
window.addEventListener("popstate", () =>
  show(location.hash.slice(1) || pages[0].id, { push: false }),
);
