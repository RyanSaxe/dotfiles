/**
 * The frame: a top bar, the thread of questions with the composer, the page,
 * and the code pane beside it when a reference opens it. Every control has a
 * key; the list is behind ?.
 */
import { formatLocation, parseLocation } from "./grammar.mjs";
import { createRenderer } from "./markdown.mjs";
import {
  blockInstance,
  disposeBlocks,
  renderBlock,
  renderPageExtras,
} from "./blocks/index.mjs";
import { createNoteRegistry } from "./notes.mjs";
import { isOffline, request, useEmbeddedData } from "./transport.mjs";
import {
  agentListening,
  defaultPage,
  neighbors,
  stepperPills,
  threadRows,
} from "./outline.mjs";
import {
  openFile,
  disposeCode,
  moveCursor,
  extendSelection,
  cursorLocation,
  setTheme,
  stepNote,
  growFold,
} from "./code.mjs";

const $ = (id) => document.getElementById(id);
const session = JSON.parse($("session-config").textContent);
const embedded = JSON.parse($("session-data")?.textContent || "null");
if (embedded) useEmbeddedData(embedded);
const repository = embedded?.repo ?? session.repo;

const THREAD_DEFAULT_OPEN = 1280;
const PANE_STATES = ["closed", "beside", "wide"];

let state = { questions: [], repo: repository, pending: 0 };
let view = { questionId: null, pageId: null };
let focus = "page";
let renderer = null;
let pageCursor = -1;
let threadCursor = -1;
let paneState = "closed";
let threadOpen = innerWidth >= THREAD_DEFAULT_OPEN;
let attached = null;
let composing = "follow-up";
let renderedRevision = null;
const registry = createNoteRegistry();
const parsedPages = new Map();
const palette = { results: [], cursor: 0, timer: null, total: 0 };

const keyMap = [
  ["] [", "Next and previous page"],
  ["j k", "Move within the focused region"],
  ["Enter", "Switch question, open the reference or file, pick the choice"],
  ["Tab", "Move focus between the thread, the page, and the code"],
  ["o", "Open the current reference in the code pane"],
  ["w", "Cycle the code pane: beside, wide, closed"],
  ["t", "Toggle the questions"],
  ["/", "Ask a follow-up"],
  ["n", "Ask a new question"],
  ["f", "Open a file"],
  ["Shift+J Shift+K", "Extend the line selection"],
  ["a", "Ask about the selection"],
  [". ,", "Next and previous note"],
  ["- =", "Show more of the file above or below"],
  ["y", "Copy path:line"],
  ["1–9", "Pick a choice option"],
  ["e", "Export"],
  ["?", "This list"],
  ["Esc", "Leave the box, close what is open, clear the selection"],
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
  if (preferredTheme) document.documentElement.dataset.theme = preferredTheme;
  else delete document.documentElement.dataset.theme;
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
  const response = await request("/api/ask", {
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
  if (isOffline()) return;
  await request("/api/choose", {
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

/* ------------------------------------------------------------- top bar ---- */

function paintStepper() {
  const nav = $("stepper");
  nav.replaceChildren();
  for (const pill of stepperPills(state, view)) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "pg";
    button.classList.toggle("written", pill.written);
    button.classList.toggle("current", pill.current);
    button.classList.toggle("writing", pill.writing);
    button.disabled = !pill.written;
    button.title = pill.title;
    button.textContent = pill.current
      ? `${pill.n} · ${pill.title}`
      : String(pill.n);
    if (pill.writing)
      button.append(
        Object.assign(document.createElement("span"), { className: "spin" }),
      );
    else if (pill.updated && !pill.current)
      button.append(
        Object.assign(document.createElement("span"), {
          className: "dot",
          title: "Updated",
        }),
      );
    button.onclick = () => show(view.questionId, pill.id);
    nav.append(button);
  }
  const count = state.questions.length;
  $("question-count").textContent = count
    ? `${count} question${count === 1 ? "" : "s"}`
    : "Questions";
}

/* --------------------------------------------------------------- thread --- */

function paintThread() {
  const list = $("thread-list");
  list.replaceChildren();
  const rows = threadRows(state, view, isOffline() ? null : Date.now());
  if (!rows.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = isOffline()
      ? "No questions in this export."
      : "Ask about the repository to begin.";
    list.append(empty);
  }
  rows.forEach((row, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "msg";
    button.classList.toggle("current", row.current);
    if (index === threadCursor) button.dataset.cursor = "true";
    const text = document.createElement("div");
    text.className = "q";
    text.textContent = row.text;
    const line = document.createElement("div");
    line.className = "st";
    line.textContent = row.line;
    if (row.working && row.status !== "asked")
      line.append(
        Object.assign(document.createElement("span"), { className: "spin" }),
      );
    button.append(text, line);
    button.onclick = () => {
      threadCursor = index;
      if (row.firstPage)
        show(row.id, row.current ? view.pageId : row.firstPage);
      else {
        view.questionId = row.id;
        view.pageId = null;
        paintStepper();
        paintThread();
        paintPage();
      }
    };
    list.append(button);
  });
  $("thread-toggle").setAttribute("aria-pressed", String(threadOpen));
}

function setThread(open) {
  threadOpen = open;
  $("body").classList.toggle("thread-open", threadOpen);
  $("thread-toggle").setAttribute("aria-pressed", String(threadOpen));
  if (!threadOpen && focus === "thread") focus = "page";
}

/** The chips above the composer: the page it asks on, and any attached lines. */
function paintContext() {
  const box = $("ask-context");
  box.replaceChildren();
  const chip = (text, quiet = true) => {
    const element = document.createElement("span");
    element.className = quiet ? "chip quiet" : "chip";
    element.textContent = text;
    element.title = text;
    box.append(element);
  };
  const question = state.questions.find(
    (entry) => entry.id === view.questionId,
  );
  const page = question?.pages.find((entry) => entry.id === view.pageId);
  if (composing === "new" || !question) {
    chip("New question");
    $("ask-input").placeholder = "Ask about this repository…";
  } else {
    chip(page ? `On: ${page.title}` : `On: ${question.title}`);
    $("ask-input").placeholder = "Ask a follow-up…";
  }
  if (attached) chip(attached.label, false);
}

function focusComposer(mode) {
  composing = mode;
  if (mode === "new") attached = null;
  if (!threadOpen) setThread(true);
  paintContext();
  $("ask-input").focus();
}

function attach(label, context) {
  attached = { label, context };
  focusComposer("follow-up");
}

$("ask-form").onsubmit = async (event) => {
  event.preventDefault();
  const text = $("ask-input").value.trim();
  if (!text) return;
  let context = null;
  if (attached) context = attached.context;
  else if (composing !== "new" && view.questionId)
    context = { questionId: view.questionId, pageId: view.pageId };
  $("ask-input").value = "";
  $("ask-error").hidden = true;
  attached = null;
  composing = "follow-up";
  try {
    await ask(text, context);
    threadCursor = state.questions.length - 1;
    paintThread();
  } catch (error) {
    $("ask-error").hidden = false;
    $("ask-error").textContent = error.message;
  }
  paintContext();
};
$("ask-input").addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    $("ask-form").requestSubmit();
  }
});
$("thread-toggle").onclick = () => setThread(!threadOpen);
$("thread-close").onclick = () => setThread(false);

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
  // Scroll the page column, not the document.
  const column = $("main");
  const offset =
    target.getBoundingClientRect().top - column.getBoundingClientRect().top;
  if (offset < 0 || offset > column.clientHeight - 40)
    column.scrollTop += offset - column.clientHeight / 2;
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
    const answer = await request(`/repo/exists?${query}`)
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

/**
 * Keep the note registry current across every page of the session.
 *
 * A note written beside an excerpt on one page becomes a marker on the whole
 * file wherever it is opened, so the registry has to know about pages the
 * reader has not visited. Each page is parsed once per revision.
 */
async function syncNotes() {
  renderer ||= await createRenderer();
  for (const question of state.questions) {
    for (const page of question.pages) {
      if (page.status !== "written") continue;
      const key = `${question.id}/${page.id}`;
      if (parsedPages.get(key) === page.revision) continue;
      const markdown = await request(
        `/api/page?question=${encodeURIComponent(question.id)}&id=${encodeURIComponent(page.id)}`,
      ).then((response) => (response.ok ? response.text() : null));
      if (markdown === null) continue;
      const parsed = renderer.render(markdown);
      registry.setPage(key, {
        notes: parsed.notes,
        blocks: parsed.blocks,
        from: {
          questionId: question.id,
          pageId: page.id,
          questionTitle: question.title,
          pageTitle: page.title,
        },
      });
      parsedPages.set(key, page.revision);
    }
  }
}

async function paintPage() {
  const question = state.questions.find(
    (entry) => entry.id === view.questionId,
  );
  const page = question?.pages.find((entry) => entry.id === view.pageId);
  if (!question || !page) {
    $("crumb").textContent = question ? question.title : "";
    $("page-title").className = "placeholder-title";
    $("page-title").textContent = question
      ? isOffline() || agentListening(state)
        ? "Writing the first page…"
        : "No agent is listening."
      : state.questions.length
        ? "Choose a question."
        : "Ask about this repository.";
    $("page-content").replaceChildren();
    $("asked").hidden = true;
    $("previous").hidden = $("next").hidden = true;
    renderedRevision = null;
    return;
  }

  const { pages, index, previous, next } = neighbors(
    state,
    question.id,
    page.id,
  );
  $("crumb").replaceChildren(
    Object.assign(document.createElement("b"), { textContent: question.title }),
    document.createTextNode(` · page ${index + 1} of ${pages.length}`),
  );
  $("page-title").className = "";
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
    ? $("main").scrollTop
    : 0;

  const markdown = await request(
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
    registry,
    open,
    choose,
    navigate: (from) => show(from.questionId, from.pageId),
  };
  for (const mount of $("page-content").querySelectorAll("[data-block]"))
    renderBlock(mount, rendered.blocks[Number(mount.dataset.block)], context);
  await renderPageExtras($("page-content"));
  await upgradeReferences($("page-content"), repository.ref);
  $("main").scrollTop = keepScroll;
  pageCursor = -1;
}

function show(questionId, pageId) {
  view.questionId = questionId;
  view.pageId = pageId;
  paintStepper();
  paintThread();
  paintContext();
  paintPage();
}

/* ------------------------------------------------------------ code pane --- */

function setPane(next) {
  paneState = next;
  for (const name of PANE_STATES)
    $("body").classList.toggle(name, name === next && next !== "closed");
  if (next !== "closed" && innerWidth < THREAD_DEFAULT_OPEN) setThread(false);
  if (next === "closed") {
    disposeCode($("code-body"));
    if (focus === "code") focus = "page";
  }
}

function cyclePane() {
  const at = PANE_STATES.indexOf(paneState);
  const next = PANE_STATES[(at + 1) % PANE_STATES.length];
  if (next !== "closed" && !$("code-path").textContent) return;
  setPane(next);
}

/** Open a location in the code pane, beside the page unless it is already wider. */
export async function open(text) {
  const location = typeof text === "string" ? parseLocation(text) : text;
  if (!location) return;
  if (paneState === "closed") setPane("beside");
  const ref = location.ref ?? repository.ref;
  $("code-path").textContent = location.path;
  // Notes may be written against an explicit ref or against the session's, so
  // a file opened without one still finds the notes written with it.
  const notes = [
    ...registry.forTarget(`${location.path}@${location.ref ?? ""}`),
    ...(location.ref ? [] : registry.forTarget(`${location.path}@${ref}`)),
  ];
  const meta = () =>
    `${ref}${notes.length ? ` · ${notes.length} note${notes.length === 1 ? "" : "s"}` : ""}`;
  $("code-meta").textContent = meta();
  await openFile($("code-body"), {
    path: location.path,
    ref,
    line: location.start,
    end: location.end,
    theme: activeTheme(),
    notes,
    navigate: (from) => show(from.questionId, from.pageId),
    onCursor: (line) => {
      $("code-meta").textContent = line ? `${meta()} · line ${line}` : meta();
    },
  });
  focus = "code";
}

$("code-close").onclick = () => setPane("closed");
$("code-widen").onclick = () =>
  setPane(paneState === "wide" ? "beside" : "wide");

/* ----------------------------------------------------------- quick open --- */

async function paintPalette() {
  const query = $("palette-input").value.trim();
  const results = $("palette-results");
  results.replaceChildren();
  if (!query) {
    palette.results = [];
    $("palette-count").textContent = "";
    return;
  }
  const found = await request(
    `/repo/paths?q=${encodeURIComponent(query)}&limit=50&ref=${encodeURIComponent(repository.ref)}`,
  ).then((response) => response.json());
  palette.results = found.matches ?? [];
  palette.total = found.total ?? 0;
  palette.cursor = Math.min(
    palette.cursor,
    Math.max(0, palette.results.length - 1),
  );
  palette.results.forEach(({ path, positions }, index) => {
    const button = document.createElement("button");
    button.type = "button";
    if (index === palette.cursor) button.dataset.cursor = "true";
    const cut = path.lastIndexOf("/") + 1;
    const dir = document.createElement("span");
    dir.className = "dir";
    dir.append(...markedText(path.slice(0, cut), positions, 0));
    const name = document.createElement("span");
    name.append(...markedText(path.slice(cut), positions, cut));
    button.append(dir, name);
    button.onclick = () => openFromPalette(index);
    results.append(button);
  });
  const scope = isOffline() ? "files in this export" : "tracked files";
  $("palette-count").textContent = palette.results.length
    ? `${palette.results.length} of ${(found.tracked ?? palette.total).toLocaleString()} ${scope}`
    : "no matches";
}

/** `text` with the matched characters wrapped in <mark>; `offset` is where it starts in the path. */
function markedText(text, positions, offset) {
  const nodes = [];
  let plain = "";
  for (const [index, character] of [...text].entries()) {
    if (positions.includes(offset + index)) {
      if (plain) nodes.push(plain);
      plain = "";
      nodes.push(
        Object.assign(document.createElement("mark"), {
          textContent: character,
        }),
      );
    } else plain += character;
  }
  if (plain) nodes.push(plain);
  return nodes;
}

function openFromPalette(index) {
  const match = palette.results[index];
  if (!match) return;
  $("palette").close();
  open({ path: match.path, ref: null, start: null, end: null });
}

function openPalette() {
  $("palette-input").value = "";
  paintPalette();
  $("palette").showModal();
  $("palette-input").focus();
}

$("palette-input").oninput = () => {
  clearTimeout(palette.timer);
  palette.timer = setTimeout(paintPalette, 120);
};
$("palette-input").addEventListener("keydown", (event) => {
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    const delta = event.key === "ArrowDown" ? 1 : -1;
    palette.cursor = Math.max(
      0,
      Math.min(palette.results.length - 1, palette.cursor + delta),
    );
    for (const [index, button] of [...$("palette-results").children].entries())
      if (index === palette.cursor) button.dataset.cursor = "true";
      else delete button.dataset.cursor;
    $("palette-results").children[palette.cursor]?.scrollIntoView({
      block: "nearest",
    });
  } else if (event.key === "Enter") {
    event.preventDefault();
    openFromPalette(palette.cursor);
  }
});
$("open-files").onclick = openPalette;

/* ------------------------------------------------------------- keyboard --- */

// Clicking in a region makes it the one the keys act on, and takes the keys
// back from a box the reader had been typing in.
for (const [id, region] of [
  ["thread", "thread"],
  ["main", "page"],
  ["code", "code"],
])
  $(id).addEventListener("pointerdown", (event) => {
    focus = region;
    if (typing() && !event.target.closest("form, input, textarea, select"))
      document.activeElement.blur();
  });

const typing = () =>
  document.activeElement &&
  ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName);
const dialogOpen = () => Boolean(document.querySelector("dialog[open]"));

function moveThreadCursor(delta) {
  const rows = [...$("thread-list").querySelectorAll(".msg")];
  if (!rows.length) return;
  threadCursor = Math.max(0, Math.min(rows.length - 1, threadCursor + delta));
  rows.forEach((row, index) => {
    if (index === threadCursor) row.dataset.cursor = "true";
    else delete row.dataset.cursor;
  });
  rows[threadCursor].scrollIntoView({ block: "nearest" });
}

document.addEventListener("keydown", async (event) => {
  if (event.key === "Escape") {
    if (typing()) {
      document.activeElement.blur();
      return;
    }
    if (dialogOpen()) return;
    if (paneState !== "closed") return setPane("closed");
    if (threadOpen && innerWidth < 720) return setThread(false);
    return;
  }
  if (
    typing() ||
    dialogOpen() ||
    event.metaKey ||
    event.ctrlKey ||
    event.altKey
  )
    return;

  const regions = [
    ...(threadOpen ? ["thread"] : []),
    "page",
    ...(paneState === "closed" ? [] : ["code"]),
  ];
  // Shift+J reaches some clients as "J" and others as "j" with shiftKey set,
  // so the modifier decides rather than the letter's case.
  const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
  switch (key) {
    case "Tab": {
      event.preventDefault();
      const at = Math.max(0, regions.indexOf(focus));
      focus =
        regions[
          (at + (event.shiftKey ? regions.length - 1 : 1) + regions.length) %
            regions.length
        ];
      $(
        focus === "page"
          ? "main"
          : focus === "code"
            ? "code-body"
            : "thread-list",
      ).focus();
      return;
    }
    case "]":
    case "[": {
      const { previous, next } = neighbors(state, view.questionId, view.pageId);
      const target = key === "]" ? next : previous;
      if (target) show(view.questionId, target.id);
      return;
    }
    case "j":
    case "k": {
      const delta = key === "j" ? 1 : -1;
      event.preventDefault();
      if (event.shiftKey) {
        if (focus === "code") extendSelection($("code-body"), delta);
        return;
      }
      if (focus === "thread") moveThreadCursor(delta);
      else if (focus === "code") moveCursor($("code-body"), delta);
      else movePageCursor(delta);
      return;
    }
    case "Enter":
      if (focus === "thread")
        return $("thread-list").querySelectorAll(".msg")[threadCursor]?.click();
      if (focus === "page") return currentTarget()?.click();
      return;
    case "o":
      if (focus === "page") return currentTarget()?.click();
      return;
    case "w":
      event.preventDefault();
      return cyclePane();
    case "t":
      event.preventDefault();
      return setThread(!threadOpen);
    case "f":
      event.preventDefault();
      return openPalette();
    case "/":
      event.preventDefault();
      if (!isOffline()) focusComposer("follow-up");
      return;
    case "n":
      event.preventDefault();
      if (!isOffline()) focusComposer("new");
      return;
    case "a": {
      event.preventDefault();
      if (isOffline()) return;
      if (focus === "code") {
        const location = cursorLocation($("code-body"));
        if (location)
          attach(formatLocation(location), {
            questionId: view.questionId,
            file: location.path,
            ref: location.ref,
            lines: [location.start, location.end],
          });
        return;
      }
      const selected = String(getSelection() ?? "").trim();
      if (selected)
        attach(`“${selected.slice(0, 60)}${selected.length > 60 ? "…" : ""}”`, {
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
    case ".":
    case ",": {
      const delta = key === "." ? 1 : -1;
      if (focus === "code") stepNote($("code-body"), delta);
      else blockInstance(currentTarget())?.step?.(delta);
      return;
    }
    case "-":
    case "=":
      if (focus === "code")
        growFold($("code-body"), key === "-" ? "above" : "below");
      return;
    case "e":
      event.preventDefault();
      return exportSession();
    case "?":
      event.preventDefault();
      return $("help").showModal();
    default:
      if (/^[1-9]$/.test(key))
        $("page-content").querySelector(`[data-option="${key}"]`)?.click();
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
$("open-help").onclick = () => $("help").showModal();
$("help-close").onclick = () => $("help").close();
for (const [keys, meaning] of keyMap) {
  const term = document.createElement("dt");
  for (const [index, key] of keys.split(" ").entries()) {
    if (index) term.append(" ");
    term.append(
      Object.assign(document.createElement("kbd"), { textContent: key }),
    );
  }
  const detail = document.createElement("dd");
  detail.textContent = meaning;
  $("help-keys").append(term, detail);
}

/**
 * Write the session to one HTML file and hand the reader both the path on
 * disk and a copy they can save from the browser.
 */
async function exportSession() {
  if (isOffline()) return;
  $("export-note").hidden = false;
  $("export-note").textContent = "Writing the export…";
  try {
    const response = await request("/api/export", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionId: session.sessionId }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error);
    $("export-note").replaceChildren();
    const line = document.createElement("span");
    line.textContent = `Exported to ${result.path}`;
    const save = document.createElement("a");
    save.href = result.url;
    save.download = result.name;
    save.textContent = "Save a copy";
    $("export-note").append(line, save);
    if (result.warning) {
      const warning = document.createElement("span");
      warning.className = "export-warning";
      warning.textContent = result.warning;
      $("export-note").append(warning);
    }
  } catch (error) {
    $("export-note").textContent = error.message;
  }
}

/* --------------------------------------------------------------- polling -- */

async function poll() {
  try {
    const response = await request("/api/state");
    if (!response.ok) throw new Error("unreachable");
    state = await response.json();
    $("offline").hidden = true;
  } catch {
    $("offline").hidden = false;
    return;
  }
  $("repo-name").textContent = state.repo.name;
  $("repo-ref").textContent =
    `· ${state.repo.ref}${state.repo.refType === "branch" ? " · committed content only" : ""}`;
  const known = state.questions.some((entry) => entry.id === view.questionId);
  if (!known || !view.pageId) {
    const fallback = defaultPage(state, view.questionId);
    if (fallback) view = { ...view, ...fallback };
    else if (!known && state.questions.length)
      view.questionId = state.questions.at(-1).id;
  } else {
    const question = state.questions.find(
      (entry) => entry.id === view.questionId,
    );
    if (!question.pages.some((page) => page.id === view.pageId))
      view.pageId = defaultPage(state, view.questionId)?.pageId ?? null;
  }
  paintStepper();
  paintThread();
  paintContext();
  await syncNotes();
  await paintPage();
}

window.addEventListener("vr:theme", () => {
  setTheme($("code-body"), activeTheme());
  renderedRevision = null;
  paintPage();
});

setThread(threadOpen);
if (isOffline()) {
  poll();
  $("ask-form").hidden = true;
  $("exported-note").hidden = false;
  $("exported-note").textContent =
    `Exported on ${new Date(embedded.state?.updatedAt ?? Date.now()).toLocaleDateString()}. Ask in a live session.`;
} else {
  // A session with nothing asked yet starts in the composer; one with an
  // answer starts on the page, where the keys read it.
  poll().then(() => {
    if (!state.questions.length) $("ask-input").focus();
  });
  setInterval(poll, 1000);
}
