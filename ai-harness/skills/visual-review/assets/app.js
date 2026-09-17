/**
 * The frame: outline on the left, the page in the middle, real code on the
 * right, and a keyboard that reaches all of it.
 */
import { formatLocation, parseLocation } from "./grammar.mjs";
import { createRenderer } from "./markdown.mjs";
import { renderBlock, disposeBlocks } from "./blocks/index.mjs";
import { defaultPage, neighbors, outlineModel } from "./outline.mjs";
import {
  openFile,
  disposeCode,
  flattenTree,
  moveCursor,
  extendSelection,
  cursorLocation,
} from "./code.mjs";

const $ = (id) => document.getElementById(id);
const session = JSON.parse($("session-config").textContent);
const repository = session.repo;

let state = { questions: [], repo: repository, pending: 0 };
let view = { questionId: null, pageId: null, collapsed: new Set() };
let focus = "page";
let renderer = null;
let pageCursor = -1;
let quote = null;
let browserOpen = false;
let browserEntries = [];
let browserCursor = 0;
let expanded = new Set([""]);
let filterTimer = null;
let renderedRevision = null;

const keyMap = [
  ["h l", "Previous and next page"],
  ["j k", "Move within the focused region"],
  ["Enter", "Open the reference, note, choice, or file"],
  ["Tab", "Move focus between outline, page, and code"],
  ["o", "Open the current reference in the code pane"],
  ["f", "Toggle the file browser"],
  ["] [", "Next and previous note"],
  ["J K", "Extend the line selection"],
  ["a", "Ask about the selection"],
  ["/ n", "Ask in this question, or start a new one"],
  ["1-9", "Pick a choice option"],
  ["y", "Copy path:line"],
  ["?", "Show this list"],
  ["Esc", "Leave the box, close the browser, clear the selection"],
];

/* ---------------------------------------------------------------- theme --- */

const systemTheme = matchMedia("(prefers-color-scheme: dark)");
let preferredTheme = null;
try {
  preferredTheme =
    document.cookie.match(/visual-review-theme=(light|dark)/)?.[1] ?? null;
} catch {
  /* A blocked cookie only costs the remembered choice. */
}
export function activeTheme() {
  return preferredTheme ?? (systemTheme.matches ? "dark" : "light");
}
function applyTheme() {
  document.documentElement.dataset.theme = activeTheme();
  window.dispatchEvent(new CustomEvent("vr:theme", { detail: activeTheme() }));
}
$("theme").value = preferredTheme ?? "system";
$("theme").onchange = () => {
  preferredTheme = $("theme").value === "system" ? null : $("theme").value;
  try {
    document.cookie = `visual-review-theme=${preferredTheme ?? ""}; Path=/; SameSite=Strict; Max-Age=${preferredTheme ? 31536000 : 0}`;
  } catch {
    /* Keep the choice for this tab when cookies are blocked. */
  }
  applyTheme();
};
systemTheme.addEventListener("change", () => {
  if (!preferredTheme) applyTheme();
});
applyTheme();

/* ------------------------------------------------------------- requests --- */

async function ask(text, context) {
  const response = await fetch("/api/ask", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      sessionId: session.sessionId,
      id: crypto.randomUUID().replaceAll("-", ""),
      text,
      context,
    }),
  });
  if (!response.ok) throw new Error((await response.json()).error);
  await poll();
}

export async function choose(questionId, pageId, blockId, option) {
  await fetch("/api/choose", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      sessionId: session.sessionId,
      id: crypto.randomUUID().replaceAll("-", ""),
      questionId,
      pageId,
      blockId,
      option,
    }),
  });
  await poll();
}

/* -------------------------------------------------------------- outline --- */

function paintOutline() {
  const model = outlineModel(state, view);
  const nav = $("outline");
  nav.replaceChildren();
  for (const question of model.questions) {
    const head = document.createElement("button");
    head.className = "question";
    head.dataset.question = question.id;
    head.setAttribute("aria-current", String(question.id === view.questionId));
    const caret = document.createElement("span");
    caret.className = "caret";
    caret.textContent = question.expanded ? "▾" : "▸";
    const title = document.createElement("span");
    title.className = "q-title";
    title.textContent = question.title;
    head.append(caret, title);
    if (!question.expanded) {
      const count = document.createElement("span");
      count.className = "q-count";
      count.textContent = `${question.pageCount} page${question.pageCount === 1 ? "" : "s"}`;
      head.append(count);
    }
    head.onclick = () => {
      if (view.collapsed.has(question.id)) view.collapsed.delete(question.id);
      else view.collapsed.add(question.id);
      paintOutline();
    };
    nav.append(head);

    if (!question.expanded) continue;
    const pages = document.createElement("div");
    pages.className = "pages";
    for (const page of question.pages) {
      const entry = document.createElement("button");
      entry.className = "page-entry";
      entry.classList.toggle("current", page.current);
      entry.classList.toggle("written", page.written);
      entry.classList.toggle("writing", page.writing);
      entry.dataset.question = question.id;
      entry.dataset.page = page.id;
      entry.disabled = !page.written;
      const label = document.createElement("span");
      label.className = "label";
      label.textContent = page.title;
      entry.append(label);
      if (page.writing) {
        const spinner = document.createElement("span");
        spinner.className = "spinner";
        entry.append(spinner);
      } else if (page.updated) {
        const dot = document.createElement("span");
        dot.className = "dot";
        dot.title = "Updated";
        entry.append(dot);
      }
      entry.onclick = () => show(question.id, page.id);
      pages.append(entry);
    }
    nav.append(pages);
  }

  const progress = model.progress;
  $("progress").hidden = !progress;
  if (progress) {
    $("progress-bar").style.width = `${Math.round(progress.fraction * 100)}%`;
    $("progress-label").textContent = progress.label;
    $("progress-status").textContent = progress.statusLine ?? "";
  }
}

/* ----------------------------------------------------------------- page --- */

function pageTargets() {
  return [...$("page-content").querySelectorAll("[data-target]")];
}

function movePageCursor(delta) {
  const targets = pageTargets();
  if (!targets.length) return;
  for (const target of targets) delete target.dataset.cursor;
  pageCursor = Math.max(0, Math.min(targets.length - 1, pageCursor + delta));
  const target = targets[pageCursor];
  target.dataset.cursor = "true";
  target.scrollIntoView({ block: "nearest" });
}

function currentTarget() {
  return pageTargets()[pageCursor] ?? null;
}

/** Confirm each candidate reference against the repository before it becomes a chip. */
async function upgradeReferences(root, ref) {
  for (const node of root.querySelectorAll("code.reference")) {
    const location = parseLocation(node.dataset.reference);
    if (!location) continue;
    const query = new URLSearchParams({
      path: location.path,
      ref: location.ref ?? ref,
    });
    const answer = await fetch(`/repo/exists?${query}`)
      .then((response) => (response.ok ? response.json() : null))
      .catch(() => null);
    if (!answer?.exists || answer.type !== "file") {
      node.classList.remove("reference");
      continue;
    }
    const chip = document.createElement("a");
    chip.className = "reference";
    chip.href = "#";
    chip.dataset.target = "reference";
    chip.dataset.location = node.dataset.reference;
    chip.textContent = formatLocation(location);
    chip.onclick = (event) => {
      event.preventDefault();
      open(node.dataset.reference);
    };
    node.replaceWith(chip);
  }
}

async function paintPage() {
  const question = state.questions.find(
    (entry) => entry.id === view.questionId,
  );
  const page = question?.pages.find((entry) => entry.id === view.pageId);
  if (!question || !page) {
    $("crumb").textContent = "";
    $("page-title").textContent = state.questions.length
      ? "Writing the first page…"
      : "Ask a question to begin.";
    $("page-content").replaceChildren();
    $("asked").hidden = true;
    $("previous").hidden = $("next").hidden = true;
    return;
  }

  const { pages, index, previous, next } = neighbors(
    state,
    question.id,
    page.id,
  );
  $("crumb").textContent =
    `${question.title} · page ${index + 1} of ${pages.length}`;
  $("page-title").textContent = page.title;
  $("asked").hidden = index !== 0;
  $("asked").textContent = question.text;
  $("previous").hidden = !previous;
  $("next").hidden = !next;
  if (previous) $("previous").textContent = `← ${previous.title}`;
  if (next) $("next").textContent = `${next.title} →`;

  const signature = `${question.id}/${page.id}/${page.revision ?? 0}`;
  if (signature === renderedRevision) return;
  const keepScroll = renderedRevision?.startsWith(`${question.id}/${page.id}/`)
    ? $("page").scrollTop
    : 0;

  const markdown = await fetch(
    `/api/page?question=${encodeURIComponent(question.id)}&id=${encodeURIComponent(page.id)}`,
  ).then((response) => response.text());
  renderer ||= await createRenderer();
  const rendered = renderer.render(markdown);

  disposeBlocks($("page-content"));
  $("page-content").innerHTML = rendered.html;
  renderedRevision = signature;

  const context = {
    ref: repository.ref,
    questionId: question.id,
    pageId: page.id,
    notes: rendered.notes,
    open,
    choose,
  };
  for (const mount of $("page-content").querySelectorAll("[data-block]"))
    renderBlock(mount, rendered.blocks[Number(mount.dataset.block)], context);
  window.dispatchEvent(
    new CustomEvent("vr:page", {
      detail: { element: $("page-content"), context },
    }),
  );
  await upgradeReferences($("page-content"), repository.ref);
  $("page").scrollTop = keepScroll;
  pageCursor = -1;
}

function show(questionId, pageId) {
  view.questionId = questionId;
  view.pageId = pageId;
  paintOutline();
  paintPage();
}

/* ------------------------------------------------------------ code pane --- */

/** Open a location in the code pane, widening the layout the first time. */
export async function open(text) {
  const location = typeof text === "string" ? parseLocation(text) : text;
  if (!location) return;
  $("code").hidden = false;
  $("app").classList.add("with-code");
  $("code-path").textContent = location.path;
  $("code-ref").textContent = `@ ${location.ref ?? repository.ref}`;
  await openFile($("code-body"), {
    path: location.path,
    ref: location.ref ?? repository.ref,
    line: location.start,
    end: location.end,
    theme: activeTheme(),
    onCursor: (line) => {
      $("code-cursor").textContent = line ? `${location.path}:${line}` : "";
    },
  });
  focus = "code";
}

function closeCode() {
  disposeCode($("code-body"));
  $("code").hidden = true;
  $("app").classList.remove("with-code");
  if (focus === "code") focus = "page";
}

/* --------------------------------------------------------- file browser --- */

const readDirectory = (directory) =>
  fetch(
    `/repo/tree?path=${encodeURIComponent(directory)}&ref=${encodeURIComponent(repository.ref)}`,
  )
    .then((response) => response.json())
    .then((result) => result.entries ?? []);

async function paintBrowser() {
  const body = $("browser-body");
  body.replaceChildren();
  const query = $("filter").value.trim();
  if (query) {
    const found = await fetch(
      `/repo/paths?q=${encodeURIComponent(query)}&limit=200&ref=${encodeURIComponent(repository.ref)}`,
    ).then((response) => response.json());
    browserEntries = found.matches.map((path) => ({
      path,
      type: "file",
      depth: 0,
    }));
  } else {
    browserEntries = await flattenTree(readDirectory, expanded);
  }
  browserCursor = Math.min(
    browserCursor,
    Math.max(0, browserEntries.length - 1),
  );
  browserEntries.forEach((entry, index) => {
    const button = document.createElement("button");
    button.className = `type-${entry.type}`;
    button.style.paddingLeft = `${10 + entry.depth * 12}px`;
    if (index === browserCursor) button.dataset.cursor = "true";
    const caret = document.createElement("span");
    caret.className = "caret";
    caret.textContent =
      entry.type === "directory" ? (expanded.has(entry.path) ? "▾" : "▸") : "";
    const name = document.createElement("span");
    name.className = "entry-name";
    name.textContent = query ? entry.path : entry.path.split("/").pop();
    button.append(caret, name);
    button.onclick = () => {
      browserCursor = index;
      activateBrowserEntry();
    };
    body.append(button);
  });
}

async function activateBrowserEntry() {
  const entry = browserEntries[browserCursor];
  if (!entry) return;
  if (entry.type === "directory") {
    if (expanded.has(entry.path)) expanded.delete(entry.path);
    else expanded.add(entry.path);
    await paintBrowser();
    return;
  }
  await open({ path: entry.path, ref: null, start: null, end: null });
}

function toggleBrowser(next = !browserOpen) {
  browserOpen = next;
  $("browser").hidden = !browserOpen;
  $("app").classList.toggle("with-browser", browserOpen);
  if (browserOpen) {
    paintBrowser();
    $("filter").focus();
    focus = "browser";
  } else if (focus === "browser") focus = "page";
}

$("filter").oninput = () => {
  clearTimeout(filterTimer);
  filterTimer = setTimeout(paintBrowser, 150);
};

/* ----------------------------------------------------------------- ask ---- */

function focusAsk(newQuestion) {
  if (newQuestion) {
    quote = null;
    $("ask-quote").hidden = true;
  }
  $("ask-input").dataset.scope = newQuestion ? "new" : "question";
  $("ask-input").placeholder = newQuestion
    ? "Ask about this repository…"
    : `Ask about ${state.questions.find((q) => q.id === view.questionId)?.title ?? "this repository"}…`;
  $("ask-input").focus();
}

function attachQuote(text, context) {
  quote = { text, context };
  $("ask-quote").hidden = false;
  $("ask-quote").textContent = text;
  focusAsk(false);
}

$("ask-form").onsubmit = async (event) => {
  event.preventDefault();
  const text = $("ask-input").value.trim();
  if (!text) return;
  const scope = $("ask-input").dataset.scope;
  let context = null;
  if (quote) context = quote.context;
  else if (scope !== "new" && view.questionId)
    context = { questionId: view.questionId, pageId: view.pageId };
  $("ask-input").value = "";
  $("ask-quote").hidden = true;
  quote = null;
  $("ask-input").blur();
  try {
    await ask(text, context);
  } catch (error) {
    $("ask-quote").hidden = false;
    $("ask-quote").textContent = error.message;
  }
};

/* ------------------------------------------------------------- keyboard --- */

const typing = () =>
  document.activeElement &&
  ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName);

document.addEventListener("keydown", async (event) => {
  if (event.key === "Escape") {
    if (typing()) {
      document.activeElement.blur();
      return;
    }
    if ($("help").open) return $("help").close();
    if (browserOpen) return toggleBrowser(false);
    if (!$("code").hidden) return closeCode();
    return;
  }
  if (typing() || event.metaKey || event.ctrlKey || event.altKey) return;

  const regions = ["outline", "page", ...($("code").hidden ? [] : ["code"])];
  switch (event.key) {
    case "Tab": {
      event.preventDefault();
      const at = regions.indexOf(focus);
      focus =
        regions[
          (at + (event.shiftKey ? regions.length - 1 : 1) + regions.length) %
            regions.length
        ];
      $(
        focus === "page" ? "main" : focus === "code" ? "code-body" : "outline",
      ).focus();
      return;
    }
    case "h":
    case "l": {
      const { previous, next } = neighbors(state, view.questionId, view.pageId);
      const target = event.key === "h" ? previous : next;
      if (target) show(view.questionId, target.id);
      return;
    }
    case "j":
    case "k": {
      const delta = event.key === "j" ? 1 : -1;
      event.preventDefault();
      if (focus === "browser") {
        browserCursor = Math.max(
          0,
          Math.min(browserEntries.length - 1, browserCursor + delta),
        );
        await paintBrowser();
      } else if (focus === "code") moveCursor($("code-body"), delta);
      else if (focus === "page") movePageCursor(delta);
      else {
        const { pages, index } = neighbors(state, view.questionId, view.pageId);
        const target =
          pages[Math.max(0, Math.min(pages.length - 1, index + delta))];
        if (target) show(view.questionId, target.id);
      }
      return;
    }
    case "J":
    case "K":
      if (focus === "code")
        extendSelection($("code-body"), event.key === "J" ? 1 : -1);
      return;
    case "Enter":
      if (focus === "browser") return activateBrowserEntry();
      if (focus === "page") return currentTarget()?.click();
      return;
    case "o":
      if (focus === "page") return currentTarget()?.click();
      return;
    case "f":
      event.preventDefault();
      return toggleBrowser();
    case "/":
      event.preventDefault();
      return focusAsk(false);
    case "n":
      event.preventDefault();
      return focusAsk(true);
    case "a": {
      event.preventDefault();
      if (focus === "code") {
        const location = cursorLocation($("code-body"));
        if (location)
          attachQuote(formatLocation(location), {
            questionId: view.questionId,
            file: location.path,
            ref: location.ref,
            lines: [location.start, location.end],
          });
        return;
      }
      const selected = String(getSelection() ?? "").trim();
      if (selected)
        attachQuote(selected, {
          questionId: view.questionId,
          pageId: view.pageId,
          quote: selected.slice(0, 500),
        });
      return;
    }
    case "y": {
      const location = cursorLocation($("code-body"));
      if (location)
        await navigator.clipboard?.writeText(formatLocation(location));
      return;
    }
    case "?":
      event.preventDefault();
      return $("help").showModal();
    default:
      if (/^[1-9]$/.test(event.key)) {
        const option = $("page-content").querySelector(
          `[data-option="${event.key}"]`,
        );
        option?.click();
      }
  }
});

$("previous").onclick = () => {
  const { previous } = neighbors(state, view.questionId, view.pageId);
  if (previous) show(view.questionId, previous.id);
};
$("next").onclick = () => {
  const { next } = neighbors(state, view.questionId, view.pageId);
  if (next) show(view.questionId, next.id);
};
$("help-close").onclick = () => $("help").close();
for (const [key, meaning] of keyMap) {
  const term = document.createElement("dt");
  term.textContent = key;
  const detail = document.createElement("dd");
  detail.textContent = meaning;
  $("help-keys").append(term, detail);
}

/* --------------------------------------------------------------- polling -- */

async function poll() {
  try {
    const response = await fetch("/api/state");
    if (!response.ok) throw new Error("unreachable");
    state = await response.json();
    $("offline").hidden = true;
  } catch {
    $("offline").hidden = false;
    return;
  }
  $("repo-name").textContent = state.repo.name;
  $("repo-meta").textContent =
    state.repo.ref +
    (state.repo.refType === "branch" ? " · committed content only" : "");
  if (!view.pageId || !state.questions.some((q) => q.id === view.questionId)) {
    const fallback = defaultPage(state, view.questionId);
    if (fallback) {
      view.questionId = fallback.questionId;
      view.pageId = fallback.pageId;
    }
  } else {
    const question = state.questions.find((q) => q.id === view.questionId);
    if (!question?.pages.some((page) => page.id === view.pageId)) {
      const fallback = defaultPage(state, view.questionId);
      view.pageId = fallback?.pageId ?? null;
    }
  }
  paintOutline();
  await paintPage();
}

window.addEventListener("vr:theme", () => {
  renderedRevision = null;
  paintPage();
});

poll();
setInterval(poll, 1000);
