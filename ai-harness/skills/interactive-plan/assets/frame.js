const $ = (id) => document.getElementById(id);
const plan = JSON.parse($("plan-data").textContent);
const session = JSON.parse($("session-config").textContent);
const base = typeof session.base === "string" ? session.base : "";
const online =
  Boolean(session.sessionId) && /^https?:$/.test(location.protocol);
/* A closed session reads like an older revision: nothing can be sent from
   it. The strip below the header says which of the two it is. */
const mode = session.preview
  ? "preview"
  : session.readonly || session.closed
    ? "readonly"
    : "live";
const editable = mode === "live";
document.documentElement.dataset.mode = mode;
const query = new URL(location.href).searchParams;
const agreements = plan.agreements || [];
const builtInAgreed = !plan.pages.some((item) => item.id === "agreed");
const pages = [
  ...plan.pages,
  ...(builtInAgreed
    ? [{ id: "agreed", title: "Agreed so far", html: "" }]
    : []),
];
// crypto.randomUUID exists only in a secure context; over plain http on a
// Tailscale address, which is how a phone reaches the hub, it is undefined.
function uuid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
}
const normalize = (text) => (text || "").replace(/\s+/g, " ").trim();
const plural = (count, word) => `${count} ${word}${count === 1 ? "" : "s"}`;
function ago(value) {
  const ms = Date.now() - Date.parse(value);
  if (!Number.isFinite(ms)) return "";
  const minutes = Math.round(ms / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  return `${Math.round(hours / 24)} d ago`;
}
function since(value) {
  const ms = Date.now() - Date.parse(value);
  if (!Number.isFinite(ms)) return "";
  const minutes = Math.round(ms / 60000);
  if (minutes < 60) return `${Math.max(minutes, 1)} min`;
  const hours = Math.round(minutes / 60);
  return hours < 24 ? `${hours} h` : `${Math.round(hours / 24)} d`;
}

const systemTheme = matchMedia("(prefers-color-scheme: dark)");
let preferredTheme = null;
try {
  if (/^https?:$/.test(location.protocol)) {
    const value = document.cookie
      .split("; ")
      .find((item) => item.startsWith("interactive-plan-theme="))
      ?.split("=")[1];
    if (["light", "dark"].includes(value)) preferredTheme = value;
  }
} catch {
  /* Theme changes remain available without storage. */
}
let activeTheme = preferredTheme || (systemTheme.matches ? "dark" : "light");

const storageKey = `interactive-plan:${session.sessionId || "offline"}:${plan.artifactId}`;
const resumeKey = `interactive-plan:resume:${session.sessionId || "offline"}`;
const placeKey = `interactive-plan:place:${session.sessionId || "offline"}`;
const prefsPrefix = `interactive-plan:prefs:${session.sessionId || "offline"}:`;
let state = emptyDraft(plan.revision);
if (editable)
  try {
    state = loadDraft(
      JSON.parse(localStorage.getItem(storageKey)),
      plan.revision,
    );
  } catch {
    /* The in-memory draft and export remain usable. */
  }
const known = {
  choices: new Set(),
  lists: new Set(),
  questions: new Set(),
  text: new Map(),
};
for (const topic of plan.pages) {
  const template = document.createElement("template");
  template.innerHTML = topic.html;
  choiceTargets(template.content, topic.id);
  for (const group of template.content.querySelectorAll("[data-choice]"))
    known.choices.add(`${topic.id}/${group.dataset.choice}`);
  for (const group of template.content.querySelectorAll("[data-multiselect]"))
    known.lists.add(`${topic.id}/${group.dataset.multiselect}`);
  for (const group of template.content.querySelectorAll("[data-question]"))
    known.questions.add(`${topic.id}/${group.dataset.question}`);
  for (const group of template.content.querySelectorAll(
    "[data-drawing-question]",
  ))
    known.questions.add(`${topic.id}/${group.dataset.drawingQuestion}`);
  known.text.set(topic.id, normalize(template.content.textContent));
}
function stale(kind, key, item) {
  if (kind === "note") {
    if (item.topic === "overall") return false;
    if (item.topic === "agreed" && builtInAgreed)
      return Boolean(
        item.agreementId &&
        !agreements.some((entry) => entry.id === item.agreementId),
      );
    if (!known.text.has(item.topic)) return true;
    return (
      Boolean(item.quote) &&
      !known.text.get(item.topic).includes(normalize(item.quote))
    );
  }
  if (kind === "answer") return !known.questions.has(key);
  if (kind === "list") return !known.lists.has(key);
  return !known.choices.has(key);
}

let page = plan.pages[0],
  remote = null,
  connected = false,
  sessions = [],
  sessionOrder = [],
  editing = null,
  noteContext = null,
  selected = "",
  selectedTarget = null,
  submissionError = "",
  noteDraftKey = "",
  renderedFeedback = null,
  answerTimer;
const charts = new Map();
const diffs = new Map();
// In-flight renderers, so a page re-render can restore the scroll position
// once the content has its height back.
const renders = new Set();
function track(task) {
  renders.add(task);
  task.finally(() => renders.delete(task)).catch(() => {});
  return task;
}
const syntaxThemes = { light: "github-light", dark: "github-dark" };
const current = () =>
  remote?.current?.artifactId === plan.artifactId &&
  remote?.current?.revision === plan.revision;
const reviewAlerts = createReviewAlerts({
  window,
  button: $("notifications"),
  sessionId: session.sessionId,
  open: (href) => location.assign(new URL(href, location.href).href),
});
const prefs = {
  get(key) {
    try {
      return localStorage.getItem(prefsPrefix + key);
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      if (value === null || value === undefined)
        localStorage.removeItem(prefsPrefix + key);
      else localStorage.setItem(prefsPrefix + key, String(value));
    } catch {
      /* Preferences are conveniences; nothing depends on them. */
    }
  },
};

function persist() {
  if (!editable) return;
  try {
    localStorage.setItem(storageKey, JSON.stringify(state));
    $("storage-status").textContent = "";
  } catch {
    $("storage-status").textContent =
      "Local storage unavailable. Export a copy to keep your feedback.";
  }
}
function save() {
  persist();
  review();
}
function theme() {
  document.documentElement.dataset.theme = activeTheme;
  for (const button of $("theme").querySelectorAll("[data-theme]"))
    button.setAttribute(
      "aria-checked",
      String(button.dataset.theme === (preferredTheme || "system")),
    );
  for (const chart of charts.values())
    chart.setOption({
      color: chartPalette(),
      ...chartTheme(chart.getOption()),
    });
  for (const viewer of diffs.values()) {
    viewer.setOptions({ ...viewer.options, theme: syntaxThemes[activeTheme] });
    viewer.rerender();
  }
  // A preview page reads the theme cookie when it loads.
  for (const frame of document.querySelectorAll(".agreement-preview iframe"))
    frame.contentWindow?.location.reload();
  // A component that bakes a colour into what it drew, rather than reading
  // a token, redraws here. The diagram is the one that does.
  window.dispatchEvent(new CustomEvent("plan:theme", { detail: activeTheme }));
}
function disposeRenderers() {
  for (const chart of charts.values()) chart.dispose();
  charts.clear();
  clearDiffs();
}
// Page changes push history so the back button and a pasted hash both work;
// re-rendering the same page, restoring after a reload, and popstate itself
// leave history alone.
/* Above 720px main scrolls and the sidebar stays; below it the body does. */
const scroller = () =>
  [document.querySelector("main"), document.querySelector(".app-body")].find(
    (el) => /auto|scroll/.test(getComputedStyle(el).overflowY),
  );
/* Where you were, so the bell's jump to another session and back lands on the
   page you left. The revision is stored with it: a new revision does not
   match and the record is ignored, which is what starts you at the top of the
   first page. */
let placeTimer = 0;
function rememberPlace() {
  clearTimeout(placeTimer);
  placeTimer = setTimeout(() => {
    try {
      localStorage.setItem(
        placeKey,
        JSON.stringify({
          revision: plan.revision,
          page: $("reading").hidden ? "feedback" : page.id,
          top: Math.round(scroller().scrollTop),
        }),
      );
    } catch {
      /* Returning to the same place is a convenience, not a requirement. */
    }
  }, 250);
}
document.addEventListener("scroll", rememberPlace, true);
function show(id, targetId = null, { keepScroll = false, push = true } = {}) {
  const top = scroller().scrollTop;
  const feedback = id === "feedback" && editable;
  $("reading").hidden = feedback;
  $("feedback").hidden = !feedback;
  if (!feedback) {
    page = pages.find((item) => item.id === id) || pages[0];
    disposeRenderers();
    $("page-title").textContent = page.title;
    chooseBlock(null);
    $("page-content").innerHTML = page.html;
    blockTargets($("page-content"), page.id);
    choiceTargets($("page-content"), page.id);
    if (page.id === "agreed" && builtInAgreed) renderAgreements();
    else {
      restoreChoices();
      restoreAnswers();
      markNotes();
      enhance($("page-content"));
    }
    window.dispatchEvent(
      new CustomEvent("plan:page", {
        detail: { page, element: $("page-content") },
      }),
    );
    // Shiki, Mermaid and the charts all change a block's height after the
    // page renders, so the marks are placed again once they settle.
    Promise.allSettled([...renders]).then(placeMarks);
  }
  closeDrawer();
  for (const button of document.querySelectorAll("#navigation [data-page]")) {
    if (button.dataset.page === (feedback ? "feedback" : page.id))
      button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  }
  const url = new URL(location.href);
  url.hash = feedback ? "feedback" : page.id;
  url.searchParams.delete("target");
  if (targetId) url.searchParams.set("target", targetId);
  if (push && url.href !== location.href) history.pushState(null, "", url);
  else history.replaceState(null, "", url);
  (feedback ? $("feedback").querySelector("h1") : $("page-title")).focus({
    preventScroll: true,
  });
  if (!keepScroll) scroller().scrollTo(0, 0);
  else if (!targetId) {
    // Replacing the page shortens it until the renderers finish, and the
    // browser clamps the scroll position meanwhile; restore it after they do.
    scroller().scrollTo(0, top);
    Promise.allSettled([...renders]).then(() => scroller().scrollTo(0, top));
  }
  rememberPlace();
  const target = targetId && $(targetId);
  if (!feedback && target && $("page-content").contains(target)) {
    for (let ancestor = target; ancestor; ancestor = ancestor.parentElement)
      if (ancestor.tagName === "DETAILS") ancestor.open = true;
    if (!target.hasAttribute("tabindex")) target.tabIndex = -1;
    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: "center" });
  }
  $("quote").hidden = true;
  closeMenus();
  review();
}

/* Notes on the text */
function findText(root, needle) {
  const target = normalize(needle);
  if (!target) return null;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const map = [];
  let text = "",
    pendingSpace = false;
  for (let node; (node = walker.nextNode());) {
    if (node.parentElement?.closest("script, style")) continue;
    const data = node.data;
    for (let index = 0; index < data.length; index++) {
      if (/\s/.test(data[index])) {
        pendingSpace = text.length > 0;
        continue;
      }
      if (pendingSpace) {
        text += " ";
        map.push(null);
        pendingSpace = false;
      }
      text += data[index];
      map.push({ node, offset: index });
    }
  }
  const index = text.indexOf(target);
  if (index < 0) return null;
  const start = map[index];
  const end = map[index + target.length - 1];
  if (!start || !end) return null;
  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset + 1);
  return range;
}
function highlight(name, ranges) {
  if (typeof CSS !== "undefined" && CSS.highlights) {
    CSS.highlights.delete(name);
    if (ranges.length) CSS.highlights.set(name, new Highlight(...ranges));
    return;
  }
  for (const range of ranges) {
    if (range.startContainer !== range.endContainer) continue;
    const mark = document.createElement("mark");
    mark.className = "note-mark";
    try {
      range.surroundContents(mark);
    } catch {
      /* Partial selections stay unmarked; the count line still reports them. */
    }
  }
}
const richContent =
  "[data-language], [data-diagram], [data-math], [data-chart], [data-prototype]";
let noteRanges = [];
function markNotes() {
  const notes = state.notes.filter((note) => note.topic === page.id);
  noteRanges = [];
  for (const note of notes) {
    if (!note.quote) continue;
    const range = findText($("page-content"), note.quote);
    if (!range || range.startContainer.parentElement?.closest(richContent))
      continue;
    noteRanges.push({ note, range });
  }
  highlight(
    "plan-note",
    noteRanges.map((item) => item.range),
  );
  placeNoteBars();
  $("note-count").hidden = !notes.length;
  $("note-count").textContent = notes.length
    ? `${plural(notes.length, "note")} on this page`
    : "";
}
// Highlights have no element to hover, so the pointer is hit-tested against
// the note ranges; overlapping notes all show in one tip.
function notesAt(x, y) {
  let node, offset;
  if (document.caretPositionFromPoint) {
    const position = document.caretPositionFromPoint(x, y);
    if (!position) return [];
    node = position.offsetNode;
    offset = position.offset;
  } else if (document.caretRangeFromPoint) {
    const range = document.caretRangeFromPoint(x, y);
    if (!range) return [];
    node = range.startContainer;
    offset = range.startOffset;
  } else return [];
  return noteRanges
    .filter(({ range }) => {
      try {
        return range.isPointInRange(node, offset);
      } catch {
        return false;
      }
    })
    .map((item) => item.note);
}
let tipNotes = "";
function showTip(event) {
  const notes = noteRanges.length ? notesAt(event.clientX, event.clientY) : [];
  const key = notes.map((note) => note.id).join();
  const tip = $("note-tip");
  if (!notes.length) {
    tip.hidden = true;
    tipNotes = "";
    $("page-content").style.cursor = "";
    return;
  }
  if (key !== tipNotes) {
    tip.replaceChildren(
      ...notes.map((note) => {
        const line = document.createElement("p");
        line.textContent = note.text;
        return line;
      }),
    );
    tipNotes = key;
  }
  tip.hidden = false;
  $("page-content").style.cursor = "pointer";
  const width = tip.offsetWidth;
  tip.style.left = `${Math.min(event.pageX + 14, innerWidth - width - 12)}px`;
  tip.style.top = `${event.pageY + 18}px`;
}
$("page-content").addEventListener("mousemove", showTip);
$("page-content").addEventListener("mouseleave", () => {
  $("note-tip").hidden = true;
  tipNotes = "";
});
$("page-content").addEventListener("click", (event) => {
  if (!editable || event.target.closest("button, a, input, textarea, summary"))
    return;
  const notes = notesAt(event.clientX, event.clientY);
  if (notes.length === 1)
    openNote(
      notes[0].topic,
      notes[0].anchor,
      notes[0].quote,
      notes[0].id,
      notes[0].agreementId,
      notes[0].target,
    );
  else if (notes.length > 1) show("feedback");
});

function openNote(
  topic,
  anchor,
  quote = "",
  id = null,
  entryId = null,
  target = null,
) {
  if (!editable) return;
  noteContext = {
    topic,
    anchor,
    quote,
    ...(entryId ? { agreementId: entryId } : {}),
    ...(target ? { target } : {}),
  };
  editing = id;
  noteDraftKey = JSON.stringify([topic, anchor, quote, id, entryId]);
  const pageTitle = pages.find((item) => item.id === topic)?.title || anchor;
  $("note-anchor").textContent =
    anchor && anchor !== pageTitle ? `${pageTitle} › ${anchor}` : pageTitle;
  $("note-quote").textContent = quote;
  $("note-quote").hidden = !quote;
  $("note-text").value =
    state.noteDrafts?.[noteDraftKey] ??
    (id ? state.notes.find((note) => note.id === id).text : "");
  settleNoteImages();
  noteImages = id
    ? [...(state.notes.find((note) => note.id === id)?.attachments || [])]
    : [];
  noteImagesAtOpen = noteImages.map((item) => item.id);
  drawNoteImages();
  imageError("");
  $("note-title").textContent = id ? "Edit note" : "Add note";
  $("note-form").querySelector('[type="submit"]').textContent = id
    ? "Save changes"
    : "Add to feedback";
  $("note-dialog").showModal();
  $("note-text").focus();
  $("quote").hidden = true;
}

/* Agreed */
function agreementLabel(entry) {
  if (entry.state === "reopened") return ["Revisiting", "attention"];
  if (entry.state === "retired") return ["No longer applies", "muted"];
  if (entry.change === "new") return ["New", ""];
  if (entry.change === "updated") return ["Updated", ""];
  return null;
}
function describeRecord(record) {
  const where =
    pages.find((item) => item.id === record.topic)?.title || record.topic;
  if (record.kind === "note") return `your note on ${where}`;
  if (record.kind === "answer") return `your answer to “${record.label}”`;
  return `your choice “${record.text}” for ${record.label}`;
}
function recordUrl(record, route) {
  const params = new URLSearchParams();
  if (record.target) params.set("target", record.target);
  if (record.quote) params.set("quote", record.quote);
  const search = params.toString();
  return `${base}/${route}/${encodeURIComponent(record.revision)}${search ? "?" + search : ""}#${encodeURIComponent(record.topic)}`;
}
function tag(text, tone = "") {
  const element = document.createElement("span");
  element.className = `tag ${tone}`.trim();
  element.textContent = text;
  return element;
}
function linkButton(text, onclick) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "link-btn";
  button.textContent = text;
  button.onclick = onclick;
  return button;
}
function agreementCard(entry) {
  const card = document.createElement("section");
  card.className = "agreement-card";
  card.id = "agreement-" + entry.id;
  const body = document.createElement("div");
  body.className = "agreement-body";
  const title = document.createElement("h2");
  title.textContent = entry.title;
  const label = agreementLabel(entry);
  if (label) title.append(tag(label[0], label[1]));
  const noteCount = state.notes.filter(
    (note) => note.agreementId === entry.id,
  ).length;
  if (noteCount) title.append(tag(plural(noteCount, "note"), "muted"));
  const content = document.createElement("div");
  content.innerHTML = entry.html;
  body.append(title, content);
  card.append(body);
  const records = entry.sourceRecords || [];
  const first = records.find((record) => record.kind !== "conversation");
  const strip = document.createElement("div");
  strip.className = "agreement-source";
  const text = document.createElement("span");
  text.textContent = first
    ? `Agreed in revision ${first.revision} · ${describeRecord(first)}`
    : records.length
      ? "From the conversation"
      : entry.source
        ? "Source noted by the agent"
        : "";
  const actions = document.createElement("div");
  actions.className = "actions";
  const separator = () => {
    const dot = document.createElement("span");
    dot.textContent = "·";
    return dot;
  };
  const preview = document.createElement("div");
  preview.className = "agreement-preview";
  preview.append(document.createElement("div"));
  if (first && online) {
    const toggle = linkButton("Preview", () => {
      const open = preview.classList.toggle("open");
      toggle.textContent = open ? "Hide preview" : "Preview";
      if (open && !preview.querySelector("iframe")) {
        const frame = document.createElement("iframe");
        frame.title = `Revision ${first.revision}: ${describeRecord(first)}`;
        frame.src = recordUrl(first, "preview");
        preview.firstElementChild.append(frame);
      }
    });
    actions.append(toggle, separator());
  }
  if (first) {
    const open = document.createElement("a");
    open.textContent = "Open";
    if (online) open.href = recordUrl(first, "r");
    else {
      open.href = first.href;
      open.target = "_blank";
      open.rel = "noopener";
    }
    actions.append(open);
  }
  const details = document.createElement("div");
  details.className = "agreement-sources";
  details.hidden = true;
  const extra = records.filter((record) => record !== first);
  if (entry.source) {
    const legacy = document.createElement("p");
    legacy.textContent = entry.source;
    details.append(legacy);
  }
  for (const record of extra) {
    const box = document.createElement("div");
    box.className = "record";
    const meta = document.createElement("span");
    meta.className = "small";
    meta.textContent =
      record.kind === "conversation"
        ? "Conversation · agent-provided context"
        : `Revision ${record.revision} · ${describeRecord(record)}`;
    box.append(meta);
    if (record.quote) {
      const quote = document.createElement("blockquote");
      quote.textContent = record.quote;
      box.append(quote);
    }
    const line = document.createElement("span");
    line.textContent = record.text;
    box.append(line);
    if (record.kind !== "conversation") {
      const open = document.createElement("a");
      open.className = "context-link";
      open.textContent = " Open";
      if (online) open.href = recordUrl(record, "r");
      else {
        open.href = record.href;
        open.target = "_blank";
        open.rel = "noopener";
      }
      box.append(open);
    }
    details.append(box);
  }
  if (entry.href) {
    const link = document.createElement("a");
    link.href = entry.href;
    link.target = "_blank";
    link.rel = "noopener";
    link.textContent = "Open source ↗";
    details.append(link);
  }
  if (details.children.length) {
    if (actions.children.length) actions.append(separator());
    const count = extra.length + (entry.source ? 1 : 0) + (entry.href ? 1 : 0);
    const more = linkButton(
      first ? `${count} more` : count > 1 ? `${count} sources` : "Details",
      () => {
        details.hidden = !details.hidden;
      },
    );
    actions.append(more);
  }
  if (editable) {
    if (actions.children.length) actions.append(separator());
    actions.append(
      linkButton("Comment", () =>
        openNote("agreed", entry.title, "", null, entry.id, card.id),
      ),
    );
  }
  strip.append(text, actions);
  card.append(strip, details, preview);
  return card;
}
function renderAgreements() {
  const root = $("page-content");
  root.replaceChildren();
  if (!agreements.length) {
    root.innerHTML = '<p class="muted">No agreements recorded yet.</p>';
    return;
  }
  const active = agreements.filter((entry) => entry.state !== "retired");
  const retired = agreements.filter((entry) => entry.state === "retired");
  for (const entry of active) root.append(agreementCard(entry));
  if (retired.length) {
    const details = document.createElement("details");
    details.className = "agreement-retired";
    const summary = document.createElement("summary");
    summary.textContent = `No longer applies · ${retired.length}`;
    details.append(summary);
    for (const entry of retired) details.append(agreementCard(entry));
    root.append(details);
  }
  enhance(root);
}

/* Feedback */
function contextLink(topic, target, text = "View") {
  const link = document.createElement("a");
  link.className = "context-link";
  link.href = `${target ? "?target=" + encodeURIComponent(target) : ""}#${encodeURIComponent(topic)}`;
  link.textContent = text;
  link.onclick = (event) => {
    event.preventDefault();
    show(topic, target);
  };
  return link;
}
function itemCard({ kind, key, item }) {
  const box = document.createElement("div");
  box.className = "feedback-item" + (item.sentIn ? " sent" : "");
  const body = document.createElement("div");
  const title = document.createElement("h3");
  title.textContent =
    kind === "note"
      ? item.anchor
      : kind === "answer"
        ? `Answer · ${item.label}`
        : item.label;
  // A note on a block that names nothing has no heading to show, and an
  // empty h3 draws a blank line above the note's own words.
  title.hidden = kind === "note" && !item.anchor;
  if (item.sentIn) title.append(tag("Sent", "ok"));
  if (kind === "list" && item.sentIn && !item.touched)
    title.append(tag("Default", "muted"));
  const old = stale(kind, key, item);
  if (old && item.revision && item.revision !== plan.revision)
    title.append(tag(`from revision ${item.revision}`, "muted"));
  body.append(title);
  if (kind === "note" && item.quote) {
    const quote = document.createElement("blockquote");
    quote.textContent = item.quote;
    body.append(quote);
  }
  if (kind === "answer" && item.kind === "drawing") {
    const image = document.createElement("img");
    image.className = "drawing-preview";
    image.src = `${base}/api/upload/${encodeURIComponent(item.previewId)}`;
    image.alt = `Drawing answer: ${item.label}`;
    body.append(image);
  } else {
    const text = document.createElement("p");
    text.textContent =
      kind === "choice" || kind === "list" ? choiceText(item) : item.text;
    body.append(text);
  }
  /* What the reviewer attached, where they check what they are about to
     send. The hub still holds the bytes, so this is the same image the
     agent will open. */
  if (kind === "note" && item.attachments?.length) {
    const strip = document.createElement("div");
    strip.className = "note-images";
    for (const image of item.attachments) {
      const thumb = document.createElement("img");
      thumb.src = `${base}/api/upload/${encodeURIComponent(image.id)}`;
      thumb.alt = "";
      thumb.className = "note-image";
      strip.append(thumb);
    }
    body.append(strip);
  }
  const topicExists =
    item.topic === "agreed" ? builtInAgreed : known.text.has(item.topic);
  if (item.topic !== "overall" && topicExists)
    body.append(
      contextLink(
        item.topic,
        kind === "note" ? item.target : item.target,
        kind === "note" ? "View" : "Edit on the page",
      ),
    );
  box.append(body);
  const actions = document.createElement("div");
  actions.className = "feedback-item-actions";
  const action = (label, onclick) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn quiet";
    button.textContent = label;
    button.onclick = onclick;
    actions.append(button);
  };
  if (!item.sentIn) {
    if (kind === "note") {
      action("Edit", () =>
        openNote(
          item.topic,
          item.anchor,
          item.quote,
          item.id,
          item.agreementId,
          item.target,
        ),
      );
      action("Remove", () => {
        forgetImages(item.attachments);
        state.notes = state.notes.filter((note) => note.id !== item.id);
        save();
        if (item.topic === page.id) show(page.id, null, { keepScroll: true });
      });
    } else if (kind === "choice") {
      action("Add comment", () =>
        openNote(
          item.topic,
          item.label,
          choiceText(item),
          null,
          null,
          item.target,
        ),
      );
      action("Clear choice", () => {
        delete state.choices[key];
        restoreChoices();
        save();
      });
    } else if (kind === "answer") {
      action("Remove", () => {
        delete state.answers[key];
        restoreAnswers();
        save();
      });
    }
  }
  box.append(actions);
  return box;
}
function renderFeedback() {
  // An untouched, unsent list is not feedback yet; it appears once it went
  // with a round, marked as a default.
  const items = [
    ...Object.entries(state.choices)
      .filter(
        ([, item]) => item.kind !== "multiple" || item.touched || item.sentIn,
      )
      .map(([key, item]) => ({
        kind: item.kind === "multiple" ? "list" : "choice",
        key,
        item,
        topic: item.topic,
      })),
    ...Object.entries(state.answers).map(([key, item]) => ({
      kind: "answer",
      key,
      item,
      topic: item.topic,
    })),
    ...state.notes.map((item) => ({
      kind: "note",
      key: item.id,
      item,
      topic: item.topic,
    })),
  ];
  const groups = $("feedback-groups");
  groups.replaceChildren();
  const group = (heading, entries) => {
    if (!entries.length) return;
    const section = document.createElement("section");
    section.className = "feedback-group";
    const head = document.createElement("div");
    head.className = "group-head";
    const title = document.createElement("h2");
    title.textContent = heading;
    head.append(title);
    section.append(head, ...entries.map(itemCard));
    groups.append(section);
  };
  for (const topic of pages)
    group(
      topic.title,
      items.filter((entry) => entry.topic === topic.id),
    );
  const orphans = items.filter(
    (entry) =>
      entry.topic !== "overall" && !pages.some((p) => p.id === entry.topic),
  );
  for (const revision of new Set(orphans.map((entry) => entry.item.revision)))
    group(
      revision ? `From revision ${revision}` : "From an earlier revision",
      orphans.filter((entry) => entry.item.revision === revision),
    );
  if (!items.some((entry) => entry.topic !== "overall")) {
    const empty = document.createElement("p");
    empty.className = "feedback-empty";
    empty.textContent = "Nothing marked yet.";
    groups.append(empty);
  }
  $("overall-notes").replaceChildren(
    ...items.filter((entry) => entry.topic === "overall").map(itemCard),
  );
}
function badge(count) {
  const row = $("review-row");
  if (!row) return;
  const mark = row.querySelector(".count");
  mark.textContent = count || "";
  mark.hidden = !count;
}
/* On a narrow screen the page list is a dialog, like every other panel.
   The one navigation element moves between the sidebar and the dialog, so
   the current page and the counts live in a single place. */
const narrow = matchMedia("(max-width: 720px)");
function placeNavigation() {
  const target = narrow.matches ? $("pages-slot") : $("sidebar-slot");
  if ($("navigation").parentElement !== target) target.append($("navigation"));
  if (!narrow.matches) closeDrawer();
}
function openDrawer() {
  $("pages-dialog").showModal();
  $("menu-button").setAttribute("aria-expanded", "true");
}
function closeDrawer() {
  if (!$("pages-dialog").open) return;
  $("pages-dialog").close();
  $("menu-button").setAttribute("aria-expanded", "false");
}
function canAccept(unsentCount) {
  return (
    plan.kind === "plan" &&
    connected &&
    current() &&
    !unsentCount &&
    ["ready", "updated"].includes(remote.stage)
  );
}
// Every page ends with where you came from and where to go next; the last
// page leads to review, and the Feedback page leads back.
function renderFooter(feedback) {
  // Agreed so far leads the order, as it leads the sidebar.
  const order = [
    ...pages.filter((item) => item.id === "agreed"),
    ...pages.filter((item) => item.id !== "agreed"),
    ...(editable ? [{ id: "feedback", title: "Feedback" }] : []),
  ];
  const index = order.findIndex(
    (item) => item.id === (feedback ? "feedback" : page.id),
  );
  const previous = order[index - 1];
  const next = order[index + 1];
  const link = (element, item, text) => {
    element.hidden = !item;
    if (!item) return;
    element.textContent = text;
    element.dataset.page = item.id;
    element.href = "#" + item.id;
  };
  if (feedback) {
    link(
      $("feedback-back"),
      previous,
      previous ? `← Back to ${previous.title}` : "",
    );
    return;
  }
  link(
    $("footer-previous"),
    previous,
    previous ? `← Previous: ${previous.title}` : "",
  );
  const acceptable = canAccept(unsentItems(state).count);
  link(
    $("footer-next"),
    next,
    !next
      ? ""
      : next.id === "feedback"
        ? acceptable
          ? "Review and accept →"
          : "Review your feedback →"
        : `Next: ${next.title} →`,
  );
}
function review() {
  const unsent = unsentItems(state);
  badge(unsent.count);
  $("accept").hidden = !canAccept(unsent.count);
  renderFooter(!$("feedback").hidden);
  const rendered = JSON.stringify([
    state.notes,
    state.choices,
    state.answers,
    state.submitted,
  ]);
  if (renderedFeedback !== rendered) {
    renderFeedback();
    renderedFeedback = rendered;
  }
  const sendable = connected && current() && editable;
  $("submit").disabled = !unsent.count || !sendable;
  $("submit").textContent = unsent.count
    ? `Submit (${unsent.count})`
    : "Submit";
  // Accept plan takes the slot on an acceptable final plan. A sent round with
  // nothing new leaves Submit in place and disabled, so the header keeps its
  // shape between rounds; the working card reports how long the agent has been
  // at it.
  $("submit").hidden = !$("accept").hidden;
  $("submit-status").textContent = submissionError;
  status();
}
function feedbackText() {
  const { notes, choices, answers } = unsentItems(state);
  const lines = [
    `Feedback: ${plan.title}`,
    `Artifact ${plan.artifactId}, revision ${plan.revision}`,
    "Feedback only. No implementation approval.",
  ];
  for (const choice of Object.values(choices))
    lines.push("", `${choice.label}: ${choiceText(choice)}`);
  for (const answer of Object.values(answers))
    lines.push(
      "",
      `${answer.label}`,
      answer.kind === "drawing"
        ? `Drawing scene ${answer.sceneId}; PNG preview ${answer.previewId}`
        : answer.text,
    );
  for (const note of notes)
    lines.push(
      "",
      note.anchor ||
        pages.find((item) => item.id === note.topic)?.title ||
        "Overall",
      ...(note.quote ? ["Selected passage: " + note.quote] : []),
      note.text,
      /* The bytes stay in the session directory, so the text names the file
         rather than carrying it. An export the reviewer mails on says the
         same, which is the only way the paths travel with it. */
      ...(note.attachments || []).map((item) => `Image: ${item.path}`),
    );
  const defaults = Object.values(state.choices).filter(
    (choice) => choice.kind === "multiple" && !choice.sentIn && !choice.touched,
  );
  if (defaults.length) lines.push("", "Defaults, not confirmed:");
  for (const choice of defaults)
    lines.push(`${choice.label}: ${choiceText(choice)}`);
  return lines.join("\n");
}
function envelope(intent, text, extra = {}) {
  return {
    sessionId: session.sessionId,
    id: uuid(),
    artifactId: plan.artifactId,
    revision: plan.revision,
    intent,
    groups: {},
    text,
    ...extra,
  };
}
async function send(event) {
  if (!connected) throw Error("The hub is unreachable. Try again shortly.");
  const response = await fetch(`${base}/api/feedback`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(event),
  });
  const result = await response.json();
  if (!response.ok) throw Error(result.error);
  if (result.status.sessionId !== session.sessionId)
    throw Error("Session identity mismatch.");
  remote = result.status;
  return result;
}

/* Status, sessions, revisions */
function scheduleReload() {
  if (
    document.querySelector("dialog[open]") ||
    ["TEXTAREA", "INPUT"].includes(document.activeElement?.tagName)
  )
    return;
  // A new revision opens at the top of its first page; the unsent draft is
  // stored separately and carries over on its own.
  try {
    sessionStorage.setItem(resumeKey, JSON.stringify({ first: true }));
  } catch {
    /* Reload without the marker. */
  }
  location.reload();
}
// Under a minute reads "just now"; after that the bare duration, as the card
// shows it beside the title.
function elapsed(value) {
  const ms = Date.now() - Date.parse(value);
  return Number.isFinite(ms) && ms < 60000 ? "just now" : since(value);
}
// The bookends are derived here, not stored: the hub only keeps the steps the
// agent declared. Rows carry "done", "now", "wait", or nothing.
function workingModel(accepting) {
  if (accepting)
    return {
      title: "Plan accepted",
      since: state.acceptance?.at || remote.updatedAt,
      bar: false,
      rows: [{ text: "Recording your acceptance", state: "now" }],
    };
  const sent = state.submitted?.revision === plan.revision;
  const read = sent
    ? plural(state.submitted.count, "comment")
    : "your feedback";
  const next = /^\d+$/.test(plan.revision)
    ? `revision ${Number(plan.revision) + 1}`
    : "the next revision";
  const publish = { text: `Publish ${next}`, state: "" };
  if (remote.stage === "submitted")
    return {
      title: "Sent",
      since: sent ? state.submitted.at : remote.updatedAt,
      bar: true,
      rows: [
        { text: `Waiting for the agent to read ${read}`, state: "wait" },
        { text: "Work out the steps", state: "" },
        { text: "Check and polish", state: "" },
        publish,
      ],
    };
  const steps = remote.progress?.steps;
  const done = { text: `Read ${read}`, state: "done" };
  const title = `Working on ${next}`;
  const since = remote.acknowledgedAt || remote.updatedAt;
  if (!steps)
    return {
      title,
      since,
      bar: true,
      rows: [
        done,
        { text: "Working out the steps", state: "now" },
        { text: "Check and polish", state: "" },
        publish,
      ],
    };
  // Steps are a set: each row shows its own state, and several can be
  // active at once.
  const finished = steps.every((step) => step.state === "done");
  return {
    title,
    since,
    bar: true,
    rows: [
      done,
      ...steps.map((step) => ({
        text: step.title,
        state:
          step.state === "done" ? "done" : step.state === "active" ? "now" : "",
      })),
      { text: "Check and polish", state: finished ? "now" : "" },
      publish,
    ],
  };
}
function renderWorking(model) {
  $("working-title").textContent = model.title;
  $("working-time").textContent = model.since ? elapsed(model.since) : "";
  // A step the agent started and never reported on looks like work; after
  // two minutes without a report the card says so.
  const report = remote?.progress?.updatedAt || remote?.acknowledgedAt;
  const stale =
    remote?.stage === "working" &&
    report &&
    Date.now() - Date.parse(report) >= 120000;
  $("working-report").hidden = !stale;
  if (stale) $("working-report").textContent = `Last report ${ago(report)}`;
  // Declared steps with none active and some pending: the agent is between
  // reports, and the card says so instead of looking idle.
  const steps = remote?.progress?.steps;
  $("working-between").hidden =
    stale ||
    remote?.stage !== "working" ||
    !Array.isArray(steps) ||
    steps.length === 0 ||
    steps.some((step) => step.state === "active") ||
    steps.every((step) => step.state === "done");
  const note = remote?.paused
    ? `The agent stopped at your request (${remote.paused.reason}). Send it a message in the chat to resume.`
    : remote?.wake?.last?.ok === false
      ? `The agent could not be woken (${remote.wake.last.reason}). Send it a message in the chat.`
      : "";
  $("working-note").hidden = !note;
  if (note) $("working-note").textContent = note;
  const bar = $("working-bar");
  const list = $("working-steps");
  bar.hidden = !model.bar;
  while (bar.children.length > model.rows.length) bar.lastElementChild.remove();
  while (list.children.length > model.rows.length)
    list.lastElementChild.remove();
  while (bar.children.length < model.rows.length)
    bar.append(document.createElement("i"));
  // Rows added after the first render slide in; the class leaves with the
  // animation so later polls compare plain state classes.
  const grown = list.children.length > 0;
  while (list.children.length < model.rows.length) {
    const row = document.createElement("li");
    if (grown) {
      row.classList.add("enter");
      row.addEventListener(
        "animationend",
        () => row.classList.remove("enter"),
        {
          once: true,
        },
      );
    }
    list.append(row);
  }
  model.rows.forEach((row, index) => {
    const segment = bar.children[index];
    const item = list.children[index];
    const state = row.state === "wait" ? "" : row.state;
    if (segment.className !== state) segment.className = state;
    const entering = item.classList.contains("enter");
    const className = entering ? `${row.state} enter`.trim() : row.state;
    if (item.className !== className) item.className = className;
    if (item.textContent !== row.text) item.textContent = row.text;
  });
}
function status() {
  const stage = !connected ? "disconnected" : remote?.stage || "ready";
  const newer = connected && remote?.current && !current();
  const accepting =
    state.acceptance && remote?.latestSubmissionId === state.acceptance.id;
  const working =
    editable &&
    connected &&
    current() &&
    ["submitted", "working"].includes(stage);
  document.body.classList.toggle("is-working", working);
  $("working").hidden = !working;
  if (working) renderWorking(workingModel(accepting));
  const complete = stage === "complete" && remote?.accepted;
  $("accepted").hidden = !complete;
  if (complete)
    $("accepted").textContent =
      remote.accepted.mode === "implement"
        ? `Plan accepted. Implementation requested. Saved at ${remote.accepted.path}`
        : `Plan accepted and saved at ${remote.accepted.path}`;
  $("connection-status").textContent = !online
    ? "Local viewing. Feedback can be exported; live submission requires the session URL."
    : !connected
      ? "The hub is unreachable. Your draft stays here and submits when it is back."
      : "";
  // A session closed from another tab reloads into read-only, so this tab
  // cannot send anything to an agent that will never be woken again.
  if ((newer || remote?.dismissedAt) && mode === "live") scheduleReload();
}
async function poll() {
  try {
    const response = await fetch(`${base}/api/status`);
    if (!response.ok) throw Error();
    const result = await response.json();
    if (result.sessionId !== session.sessionId) throw Error("Wrong session");
    remote = result;
    connected = true;
  } catch {
    connected = false;
  }
  renderRevisions();
  review();
}
async function pollSessions() {
  try {
    const response = await fetch("/api/sessions");
    if (!response.ok) throw Error();
    sessions = (await response.json()).sessions || [];
  } catch {
    sessions = [];
  }
  renderSessions();
  void reviewAlerts.update(sessions);
}
function stateWords(entry) {
  if (entry.needsYou)
    return entry.kind === "plan" ? "Ready to accept" : "Waiting for you";
  if (entry.paused) return "Paused";
  if (["submitted", "working"].includes(entry.stage))
    return `Working · ${since(entry.updatedAt)}`;
  return "Live";
}
// Every direct child of the page content is a block and gets a comment
// control, whatever it is; paragraphs, headings and lists are the exception,
// since their text is what selection comments are for.
const blockSkip = new Set([
  "P",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
  "UL",
  "OL",
  "HR",
  "BR",
  "SCRIPT",
  "STYLE",
  "TEMPLATE",
]);
// The nearest heading before the block, which is how a reader would say
// where it is. A page cannot repeat its own title in one, the build refuses
// that, so this can no longer echo the page name back.
function headingAbove(block) {
  let previous = block.previousElementSibling;
  while (previous && !/^H[1-6]$/.test(previous.tagName))
    previous = previous.previousElementSibling;
  return previous;
}
const sentence = (kind) =>
  kind.replace(/^(this|these) /, "").replace(/^./, (c) => c.toUpperCase());
function blockHeading(block) {
  const name = blockName(block);
  /* Two blocks under one heading, or two of a kind with no heading at all,
     take the same name, and Feedback lists them with nothing else to tell
     them apart. Number them only when they collide. */
  const peers = [...block.parentElement.children].filter(
    (other) => !blockSkip.has(other.tagName) && blockName(other) === name,
  );
  return peers.length < 2 ? name : `${name} ${peers.indexOf(block) + 1}`;
}
function blockName(block) {
  const read = (node) => normalize(node?.textContent);
  /* What the block gives for a name, in the order a reader would pick: its
     own heading, the title an author set, the title the frame drew for a
     figure, then the caption. Never the block's text, which is a table's
     cells, a renderer's injected stylesheet and its buttons. A block that
     gives no name returns none, and the note is filed under its page. */
  const named = "[data-title], [data-caption], [data-file]";
  const titled = block.matches(named) ? block : block.querySelector(named);
  /* A heading inside a closed details is a section of the block's source,
     not a name for it: the diff's own "Before" and "Git patch" live there. */
  const heading = [...block.querySelectorAll("h1, h2, h3, h4, h5, h6")].find(
    (node) => !node.closest("details"),
  );
  const name =
    read(heading) ||
    normalize(titled?.dataset.title) ||
    normalize(titled?.dataset.file) ||
    read(block.querySelector(".figure-head b")) ||
    normalize(titled?.dataset.caption) ||
    read(block.querySelector(".figure-caption")) ||
    /* Feedback lists every note together and the agent reads them as text,
       and in neither place is the block on screen to look at. A block that
       names nothing takes the heading it sits under, then what it is. */
    read(headingAbove(block)) ||
    sentence(blockKind(block));
  return name.length > 60 ? name.slice(0, 57) + "…" : name;
}
function renderSessions() {
  const others = sessions.filter((entry) => entry.id !== session.sessionId);
  const need = others.filter((entry) => entry.needsYou);
  const workingList = others.filter((entry) => !entry.needsYou);
  const mine = sessions.filter((entry) => entry.id === session.sessionId);
  // The number means attention: other sessions waiting on you. With none, the
  // bell stays as a plain way into the session list.
  $("bell").hidden = !others.length;
  $("bell-count").textContent = String(need.length);
  $("bell-count").hidden = !need.length;
  $("bell").classList.toggle("need", need.length > 0);
  $("bell").setAttribute(
    "aria-label",
    need.length
      ? `${plural(need.length, "session")} need you, ${plural(others.length, "other session")} live`
      : plural(others.length, "other session"),
  );
  document.title = (need.length ? `(${need.length}) ` : "") + plan.title;
  if (!others.length) toggleSidecar(false);
  sessionOrder = [...need, ...workingList, ...mine];
  const list = $("sidecar-list");
  list.replaceChildren();
  // Status first, two lines, nothing on the right: the sessions waiting on
  // you, a gap, then the rest, with this tab tinted.
  for (const [index, entry] of sessionOrder.entries()) {
    if (index === need.length && need.length && index < sessionOrder.length) {
      const gap = document.createElement("div");
      gap.className = "session-gap";
      list.append(gap);
    }
    const current = entry.id === session.sessionId;
    const row = document.createElement("button");
    row.type = "button";
    row.className =
      "session-row" +
      (entry.needsYou ? " need" : "") +
      (current ? " current" : "") +
      (entry.stage === "complete" ? " done" : "");
    const title = document.createElement("span");
    title.className = "title";
    title.textContent = entry.title;
    const close = document.createElement("button");
    close.type = "button";
    close.className = "icon-btn session-dismiss";
    close.setAttribute("aria-label", `Close ${entry.title}`);
    close.textContent = "✕";
    const words = document.createElement("span");
    words.className = "words";
    const state = document.createElement("em");
    state.textContent = current ? "This tab" : stateWords(entry);
    words.append(
      state,
      ` · ${entry.kind === "plan" ? "final plan" : "exploration"} · revision ${entry.revision} · ${ago(entry.updatedAt)}`,
    );
    row.append(title, words);
    row.onclick = () => {
      if (current) toggleSidecar(false);
      else location.assign(entry.url);
    };
    // The row is a button, so the close control is its sibling rather than
    // a button inside one.
    const line = document.createElement("div");
    line.className = "session-line";
    line.append(row);
    if (!current) {
      line.append(close);
      close.onclick = async (event) => {
        event.stopPropagation();
        /* Two round trips, a dismiss and a poll, so the row says it is going
           before either starts. Without it a slow hub looks like a dead
           control. */
        close.disabled = true;
        line.dataset.closing = "true";
        try {
          const response = await fetch(`${entry.url}api/dismiss`, {
            method: "POST",
          });
          if (!response.ok) throw Error();
          await poll();
        } catch {
          delete line.dataset.closing;
          close.disabled = false;
          state.textContent = "Could not close";
        }
      };
    }
    list.append(line);
  }
}
function renderRevisions() {
  const entries = (
    remote?.revisions?.length
      ? remote.revisions
      : [{ revision: plan.revision, publishedAt: null }]
  )
    .slice()
    .reverse();
  const latest = remote?.current?.revision ?? entries[0].revision;
  const list = $("revision-list");
  list.replaceChildren();
  for (const entry of entries) {
    const here = entry.revision === plan.revision;
    const row = document.createElement("button");
    row.type = "button";
    row.className = "rev-row" + (here ? " current" : "");
    const tick = document.createElement("span");
    tick.className = "tick";
    tick.textContent = here ? "✓" : "";
    const label = document.createElement("span");
    label.textContent = `Revision ${entry.revision}`;
    // The plan's name lives here, because the frame shows it nowhere else.
    if (here) {
      const name = document.createElement("small");
      name.textContent = plan.title;
      label.append(document.createElement("br"), name);
    }
    const time = document.createElement("small");
    time.textContent = entry.publishedAt ? ago(entry.publishedAt) : "";
    row.append(tick, label, time);
    row.onclick = () => {
      toggleRevisionMenu(false);
      if (here && mode === "live") return;
      location.assign(
        entry.revision === latest
          ? `${base}/`
          : entry.url || `${base}/r/${encodeURIComponent(entry.revision)}`,
      );
    };
    list.append(row);
  }
  // An older revision is read-only, and the clock alone does not say which
  // one you are on, so a strip under the header names it. A closed session
  // is read-only on its current revision, and there is nowhere to go back
  // to, so the strip says that instead and drops the link.
  const older = mode === "readonly";
  $("older-strip").hidden = !older;
  $("revision").classList.toggle("older", older);
  $("older-text").textContent = !older
    ? ""
    : session.closed
      ? "This plan was closed. It is here to read."
      : `You are reading revision ${plan.revision} of ${latest}`;
  $("revision-back").hidden = Boolean(session.closed);
  $("revision-back").href = `${base}/`;
  $("revision").setAttribute(
    "aria-label",
    `Revisions, on revision ${plan.revision}`,
  );
}
function toggleRevisionMenu(open = !$("revision-dialog").open) {
  if (open) $("revision-dialog").showModal();
  else if ($("revision-dialog").open) $("revision-dialog").close();
}
function toggleSidecar(open = !$("sessions-dialog").open) {
  if (open && $("bell").hidden) return;
  if (open) $("sessions-dialog").showModal();
  else if ($("sessions-dialog").open) $("sessions-dialog").close();
}
/* Escape, and every page change. A component with a popover of its own
   listens for plan:dismiss; the frame cannot reach inside one to close it. */
function closeMenus() {
  chooseBlock(null);
  window.dispatchEvent(new CustomEvent("plan:dismiss"));
  closeDrawer();
  toggleRevisionMenu(false);
  toggleSidecar(false);
  if ($("settings-dialog").open) $("settings-dialog").close();
}

/* Choices, checklists, answers */
// A note on a block carries the block's ID so Feedback can jump back to it.
function blockTargets(root, topic) {
  [...root.children].forEach((block, index) => {
    if (!blockSkip.has(block.tagName)) block.id ||= `block-${topic}-${index}`;
  });
}
function choiceTargets(root, topic) {
  for (const type of ["choice", "multiselect", "question"])
    root.querySelectorAll(`[data-${type}]`).forEach((group, index) => {
      group.id ||= `${type}-${topic}-${index}`;
    });
}
function checklist(group, topic, previous) {
  return {
    kind: "multiple",
    topic,
    label: group.dataset.label || group.dataset.multiselect,
    target: group.id,
    revision: plan.revision,
    touched: previous?.touched === true,
    options: Array.from(
      group.querySelectorAll('input[type="checkbox"][data-value]'),
      (input) => ({
        value: input.dataset.value,
        label: input.dataset.label || input.dataset.value,
        checked:
          previous?.options?.find(
            (option) => option.value === input.dataset.value,
          )?.checked ?? input.checked,
      }),
    ),
  };
}
function initializeChecklists() {
  for (const topic of plan.pages) {
    const template = document.createElement("template");
    template.innerHTML = topic.html;
    choiceTargets(template.content, topic.id);
    for (const group of template.content.querySelectorAll(
      "[data-multiselect]",
    )) {
      const id = topic.id + "/" + group.dataset.multiselect;
      const previous = state.choices[id];
      state.choices[id] = {
        ...checklist(group, topic.id, previous),
        ...(previous?.sentIn ? { sentIn: previous.sentIn } : {}),
      };
    }
  }
  persist();
}
function restoreChoices() {
  document.querySelectorAll("[data-choice] [data-value]").forEach((button) => {
    const group = button.closest("[data-choice]");
    button.setAttribute(
      "aria-pressed",
      String(
        state.choices[page.id + "/" + group.dataset.choice]?.value ===
          button.dataset.value,
      ),
    );
  });
  document
    .querySelectorAll('[data-multiselect] input[type="checkbox"][data-value]')
    .forEach((input) => {
      const group = input.closest("[data-multiselect]");
      const choice = state.choices[page.id + "/" + group.dataset.multiselect];
      input.checked =
        choice?.options.find((option) => option.value === input.dataset.value)
          ?.checked ?? input.defaultChecked;
    });
}
function restoreAnswers() {
  document.querySelectorAll("[data-question] textarea").forEach((area) => {
    const group = area.closest("[data-question]");
    const key = page.id + "/" + group.dataset.question;
    area.value = state.drafts?.[key] ?? state.answers[key]?.text ?? "";
    area.readOnly = !editable;
  });
}

/* Images on a note. A screenshot pasted from the clipboard has no filename
   and no path, and a file dropped from Finder arrives as a File the browser
   will not give a path for, so the bytes go to the hub and it writes the
   file. What comes back is a reference, which is what the note and the
   draft carry; localStorage holds about 5MB and would not survive bytes. */
let noteImages = [];
let noteImagesAtOpen = [];
let noteImagesSaved = false;
const imageTypes = ["image/png", "image/jpeg", "image/webp", "image/gif"];
function drawNoteImages() {
  const box = $("note-images");
  box.replaceChildren();
  box.hidden = !noteImages.length;
  for (const item of noteImages) {
    const figure = document.createElement("figure");
    figure.className = "note-image";
    const image = document.createElement("img");
    image.src = `${base}/api/upload/${encodeURIComponent(item.id)}`;
    image.alt = "";
    const drop = document.createElement("button");
    drop.type = "button";
    drop.className = "icon-btn";
    drop.textContent = "✕";
    drop.setAttribute("aria-label", "Remove this image");
    drop.onclick = () => {
      noteImages = noteImages.filter((held) => held.id !== item.id);
      forgetImages([item]);
      drawNoteImages();
    };
    figure.append(image, drop);
    box.append(figure);
  }
}
function imageError(message) {
  const line = $("note-image-error");
  line.textContent = message;
  line.hidden = !message;
}
/* Paste, drop and the picker all arrive here. */
async function attach(files) {
  const images = [...files].filter((file) => imageTypes.includes(file.type));
  if (!images.length) {
    imageError("Attach a PNG, JPEG, WebP or GIF.");
    return;
  }
  imageError("");
  for (const file of images) {
    try {
      const response = await fetch(`${base}/api/upload`, {
        method: "POST",
        body: file,
      });
      const record = await response.json();
      if (!response.ok) throw Error(record.error || "Upload failed.");
      noteImages.push(record);
      drawNoteImages();
    } catch (error) {
      imageError(error.message);
    }
  }
}
/* A note the reviewer dropped takes its images with it, so the session does
   not keep bytes nothing refers to. */
function forgetImages(items) {
  for (const item of items || [])
    fetch(`${base}/api/upload/${encodeURIComponent(item.id)}`, {
      method: "DELETE",
    }).catch(() => {});
}
/* A dialog the reviewer abandoned drops what it uploaded, so the session
   never keeps bytes no note refers to. This runs when the dialog is closed
   by its own control and again before the next one opens, rather than on
   the dialog's close event, which a note saved by Escape would also raise
   and which this frame cannot observe. */
function settleNoteImages() {
  if (!noteImagesSaved)
    forgetImages(
      noteImages.filter((item) => !noteImagesAtOpen.includes(item.id)),
    );
  noteImages = [];
  noteImagesAtOpen = [];
  noteImagesSaved = false;
}
$("note-image-pick").onclick = () => $("note-image-input").click();
$("note-image-input").onchange = (event) => {
  attach(event.target.files);
  event.target.value = "";
};
$("note-dialog").addEventListener("paste", (event) => {
  const files = [...event.clipboardData.items]
    .filter((item) => item.kind === "file")
    .map((item) => item.getAsFile())
    .filter(Boolean);
  if (!files.length) return;
  event.preventDefault();
  attach(files);
});
for (const type of ["dragover", "dragenter"])
  $("note-dialog").addEventListener(type, (event) => {
    event.preventDefault();
    $("note-dialog").classList.add("dropping");
  });
for (const type of ["dragleave", "drop"])
  $("note-dialog").addEventListener(type, (event) => {
    event.preventDefault();
    if (type === "dragleave" && $("note-dialog").contains(event.relatedTarget))
      return;
    $("note-dialog").classList.remove("dropping");
    if (type === "drop") attach(event.dataTransfer.files);
  });

$("note-form").onsubmit = (event) => {
  event.preventDefault();
  const text = $("note-text").value.trim();
  if (!text) return;
  const note = {
    ...noteContext,
    id: editing || uuid(),
    text,
    revision: plan.revision,
    ...(noteImages.length ? { attachments: noteImages } : {}),
  };
  if (editing)
    state.notes = state.notes.map((item) =>
      item.id === editing ? note : item,
    );
  else state.notes.push(note);
  if (state.noteDrafts) delete state.noteDrafts[noteDraftKey];
  noteImagesSaved = true;
  save();
  $("note-dialog").close();
  if (note.topic === page.id && !$("reading").hidden)
    show(page.id, null, { keepScroll: true });
};
$("submit").onclick = async () => {
  submissionError = "";
  const groups = submissionGroups(state);
  const snapshot = JSON.stringify(groups);
  if (state.pending?.snapshot !== snapshot)
    state.pending = {
      snapshot,
      event: envelope("feedback-only", feedbackText(), { groups }),
    };
  persist();
  $("submit").disabled = true;
  try {
    const result = await send(state.pending.event);
    markSent(state, result.id, new Date().toISOString());
    save();
    show(page.id, null, { keepScroll: true });
  } catch (error) {
    submissionError = error.message;
    $("submit").disabled = false;
    $("submit-status").textContent = error.message;
  }
};
$("export").onclick = () => {
  const groups = submissionGroups(state);
  const event =
    (state.pending?.snapshot === JSON.stringify(groups) &&
      state.pending.event) ||
    envelope("feedback-only", feedbackText(), { groups });
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(event, null, 2)], {
      type: "application/json",
    }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download = `${plan.artifactId}-${plan.revision}-feedback.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
};
function openAccept() {
  $("accept-detail").textContent = `${plan.title}, revision ${plan.revision}`;
  $("accept-error").textContent = "";
  $("accept-dialog").showModal();
}
$("accept").onclick = openAccept;
document.querySelectorAll("[data-accept-mode]").forEach(
  (button) =>
    (button.onclick = async () => {
      const mode = button.dataset.acceptMode;
      if (state.acceptance?.mode !== mode)
        state.acceptance = envelope(
          "accept-plan",
          `Accept ${plan.artifactId} revision ${plan.revision}. ${mode === "implement" ? "Start implementation of this plan." : "Save for later. Do not start implementation."}`,
          { mode },
        );
      document
        .querySelectorAll("[data-accept-mode]")
        .forEach((item) => (item.disabled = true));
      try {
        await send(state.acceptance);
        save();
        $("accept-dialog").close();
      } catch (error) {
        $("accept-error").textContent = error.message;
      } finally {
        document
          .querySelectorAll("[data-accept-mode]")
          .forEach((item) => (item.disabled = false));
      }
    }),
);
// A click inside an embedded frame never reaches this document, but it does
// move focus, so menus close on blur as well as on outside clicks.
window.addEventListener("blur", closeMenus);
document.addEventListener("click", (event) => {
  const close = event.target.closest("[data-close]");
  if (close) {
    if (close.dataset.close === "note-dialog") settleNoteImages();
    $(close.dataset.close).close();
  }
  const navigation = event.target.closest("[data-page]");
  if (navigation) {
    event.preventDefault();
    show(navigation.dataset.page);
  }
  if (event.target.closest("#revision")) {
    toggleRevisionMenu();
    return;
  }
  if (event.target.closest("#bell")) {
    toggleSidecar();
    return;
  }
  if (event.target.closest("#sidecar-close")) {
    toggleSidecar(false);
    return;
  }
  if (!editable) return;
  const comment = event.target.closest("[data-comment]");
  if (comment && $("page-content").contains(comment))
    openNote(
      page.id,
      comment.dataset.comment || page.title,
      "",
      null,
      null,
      comment.closest("[id]")?.id || null,
    );
  const choice = event.target.closest("[data-choice] [data-value]");
  if (choice && $("page-content").contains(choice)) {
    const group = choice.closest("[data-choice]"),
      id = page.id + "/" + group.dataset.choice;
    if (state.choices[id]?.value === choice.dataset.value)
      delete state.choices[id];
    else
      state.choices[id] = {
        topic: page.id,
        label: group.dataset.label || group.dataset.choice,
        value: choice.dataset.value,
        valueLabel:
          choice.dataset.label ||
          choice.textContent.trim() ||
          choice.dataset.value,
        target: group.id,
        revision: plan.revision,
      };
    restoreChoices();
    save();
  }
});
document.addEventListener("change", (event) => {
  if (!editable) return;
  const input = event.target.closest(
    '[data-multiselect] input[type="checkbox"][data-value]',
  );
  if (!input) return;
  const group = input.closest("[data-multiselect]");
  state.choices[page.id + "/" + group.dataset.multiselect] = {
    ...checklist(group, page.id),
    touched: true,
  };
  save();
});
document.addEventListener("input", (event) => {
  if (!editable) return;
  const area = event.target.closest("[data-question] textarea");
  if (!area || !$("page-content").contains(area)) return;
  const group = area.closest("[data-question]");
  const key = page.id + "/" + group.dataset.question;
  state.drafts ||= {};
  if (area.value.trim()) state.drafts[key] = area.value;
  else delete state.drafts[key];
  clearTimeout(answerTimer);
  answerTimer = setTimeout(save, 300);
});
/* One button, three meanings: the selection, the block you chose, or the
   page. Nothing is drawn on a block except the bar marking the chosen one. */
let chosen = null;
function placeBar() {
  const bar = $("chosen-bar");
  bar.hidden = !chosen;
  if (!chosen) return;
  const host = $("reading").getBoundingClientRect();
  const box = chosen.getBoundingClientRect();
  bar.style.top = `${Math.round(box.top - host.top)}px`;
  bar.style.height = `${Math.round(box.height)}px`;
}
function chooseBlock(block) {
  chosen?.classList.remove("is-chosen");
  chosen = block && block !== chosen ? block : null;
  chosen?.classList.add("is-chosen");
  placeBar();
  commentTarget();
}
/* A note that quotes nothing leaves no highlight to find it by, so the block
   it belongs to keeps a quiet bar in the same padding the chosen one uses.
   Accent means chosen now; muted means this block has notes. */
function placeNoteBars() {
  const host = $("note-bars");
  host.replaceChildren();
  if ($("reading").hidden) return;
  const blocks = new Set();
  for (const note of state.notes) {
    if (note.topic !== page.id || note.quote || !note.target) continue;
    const block = document
      .getElementById(note.target)
      ?.closest("#page-content > *");
    if (block) blocks.add(block);
  }
  const hostTop = $("reading").getBoundingClientRect().top;
  for (const block of blocks) {
    const box = block.getBoundingClientRect();
    const bar = document.createElement("div");
    bar.className = "note-bar";
    bar.style.top = `${Math.round(box.top - hostTop)}px`;
    bar.style.height = `${Math.round(box.height)}px`;
    host.append(bar);
  }
}
function placeMarks() {
  placeBar();
  placeNoteBars();
}
/* A tab switch, an image, or a new window width moves the block under the
   bar, and each of those changes the page's own size. */
new ResizeObserver(placeMarks).observe($("page-content"));
/* The button names what kind of thing it will comment on; the note itself
   still records the block's own heading. */
function blockKind(block) {
  const has = (selector) =>
    block.matches(selector) || block.querySelector(selector) !== null;
  /* A component names itself, so the frame never learns a component's class.
     Everything below is an attribute any component may use. */
  const declared = block.closest("[data-kind]")?.dataset.kind;
  if (declared) return `this ${declared}`;
  /* What the block is comes before what it holds, so a decision whose options
     are diagrams is still a decision. A figure is last because every diagram
     and chart contains one. */
  if (has("[data-choice]")) return "this decision";
  if (has("[data-question]")) return "this question";
  if (has("[data-multiselect]")) return "this checklist";
  if (has("table")) return "this table";
  if (has("[data-language], .shiki")) return "this code";
  if (has("[data-diagram]")) return "this diagram";
  if (has("[data-chart]")) return "this chart";
  if (has("[data-math]")) return "this formula";
  if (has("[data-prototype]")) return "this prototype";
  if (has("figure, .figure, svg, img")) return "this figure";
  return "this block";
}
function commentTarget() {
  const button = $("quote");
  /* An open dialog hides the control in CSS, which no open path can forget. */
  const usable = editable && !$("reading").hidden;
  button.hidden = !usable;
  if (!usable) return;
  if (selected.length > 3) button.textContent = "Comment on selection";
  else if (chosen) button.textContent = `Comment on ${blockKind(chosen)}`;
  else button.textContent = "Comment on this page";
}
document.addEventListener("selectionchange", () => {
  const selection = getSelection(),
    parent = selection?.anchorNode?.parentElement;
  selected = parent?.closest("#page-content")
    ? selection?.toString().trim() || ""
    : "";
  selectedTarget = parent?.closest("#page-content [id]")?.id || null;
  commentTarget();
});
/* A control does its own job, a block becomes the target, and anything else
   clears it. A drag is a selection, so it never reaches here as a press. */
$("page-content").addEventListener("click", (event) => {
  if (!editable) return;
  if (
    event.target.closest("button, a, input, label, select, textarea, summary")
  )
    return;
  if (getSelection()?.toString().trim()) return;
  const block = event.target.closest("#page-content > *");
  // A paragraph, a heading or a list is commented on by selecting its words.
  chooseBlock(block && !blockSkip.has(block.tagName) ? block : null);
});
/* The control and the c key comment on the same thing, so they share the
   one function that decides what that is. */
function commentOnTarget() {
  if (selected.length > 3)
    openNote(page.id, page.title, selected, null, null, selectedTarget);
  else if (chosen) {
    /* No quote: the note is about the block, and a quote would be searched
       for in the page and highlighted, marking the block's opening words. */
    openNote(page.id, blockHeading(chosen), "", null, null, chosen.id);
  } else openNote(page.id, page.title);
  chooseBlock(null);
}
$("quote").onpointerdown = (event) => event.preventDefault();
$("quote").onclick = commentOnTarget;
$("overall-note").onclick = () => openNote("overall", "Overall feedback");
$("note-text").oninput = () => {
  (state.noteDrafts ||= {})[noteDraftKey] = $("note-text").value;
  persist();
};
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
$("settings").onclick = () => $("settings-dialog").showModal();
$("theme").addEventListener("click", (event) => {
  const button = event.target.closest("[data-theme]");
  if (!button) return;
  preferredTheme =
    button.dataset.theme === "system" ? null : button.dataset.theme;
  activeTheme = preferredTheme || (systemTheme.matches ? "dark" : "light");
  try {
    if (/^https?:$/.test(location.protocol))
      document.cookie = `interactive-plan-theme=${preferredTheme || ""}; Path=/; SameSite=Strict; Max-Age=${preferredTheme ? 31536000 : 0}`;
  } catch {
    /* Keep the explicit choice in memory when cookies are blocked. */
  }
  theme();
});
systemTheme.addEventListener("change", () => {
  if (preferredTheme) return;
  activeTheme = systemTheme.matches ? "dark" : "light";
  theme();
});

/* Keys */
document.addEventListener("keydown", (event) => {
  /* Textareas keep Enter for newlines. Shift+Enter is the explicit submit
     gesture for the two text actions a reviewer otherwise has to click. */
  if (
    event.key === "Enter" &&
    event.shiftKey &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.altKey &&
    editable
  ) {
    const area = event.target.closest("textarea");
    const answer = area
      ?.closest("[data-question]")
      ?.querySelector("[data-answer]");
    if (answer && !answer.disabled) {
      event.preventDefault();
      answer.click();
      return;
    }
    if (area === $("note-text") && area.value.trim()) {
      event.preventDefault();
      $("note-form").requestSubmit();
      return;
    }
  }
  if (mode === "preview" || event.metaKey || event.ctrlKey || event.altKey)
    return;
  if (event.key === "Escape") {
    closeMenus();
    return;
  }
  if (event.target.closest("input, textarea, select, [contenteditable]"))
    return;
  if (document.querySelector("dialog[open]")) return;
  const key = event.key;
  if (key === "?") $("keys-dialog").showModal();
  else if (/^[1-9]$/.test(key)) {
    const entry = sessionOrder[Number(key) - 1];
    if (entry && entry.id !== session.sessionId) location.assign(entry.url);
  } else if (key === "]" || key === "[") {
    const order = pages.map((item) => item.id);
    const index = order.indexOf($("feedback").hidden ? page.id : "feedback");
    const next = order[index + (key === "]" ? 1 : -1)];
    if (next) show(next);
  } else if (key === "j" || key === "k") {
    /* The same blocks a click can choose, so the keys reach the comment
       control's target. Tab still steps through the controls inside one. */
    const blocks = [...$("page-content").children].filter(
      (block) => !blockSkip.has(block.tagName) && block.offsetParent,
    );
    if (!blocks.length) return;
    const index = blocks.indexOf(chosen);
    const next =
      blocks[
        index < 0
          ? key === "j"
            ? 0
            : blocks.length - 1
          : (index + (key === "j" ? 1 : -1) + blocks.length) % blocks.length
      ];
    // chooseBlock toggles, so landing on the current block would clear it.
    if (next !== chosen) chooseBlock(next);
    next.tabIndex = -1;
    next.focus({ preventScroll: true });
    next.scrollIntoView({ block: "center" });
  } else if (key === "c" && editable && !$("reading").hidden) commentOnTarget();
  else if (key === "r" && editable) show("feedback");
  else if (key === "s" && editable) {
    const target = $("accept").hidden ? $("submit") : $("accept");
    if (target.hidden || target.disabled) return;
    target.focus();
  } else if (key === "a") show("agreed");
  else return;
  event.preventDefault();
});

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
let diffsTask;
const color = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const chartPalette = () =>
  ["--accent", "--attention", "--ok", "--danger", "--muted"].map(color);
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
      setTimeout(() => (button.textContent = "Copy"), 1500);
    } catch {
      button.textContent = "Copy failed";
      setTimeout(() => (button.textContent = "Copy"), 1500);
    }
  };
  return button;
}
/* A JSON array in a data attribute, for the components that take one:
   data-notes on a code block, data-terms on a formula. */
function readData(value) {
  try {
    const parsed = JSON.parse(value || "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
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
function clearDiffs() {
  for (const viewer of diffs.values()) viewer.cleanUp();
  diffs.clear();
}
function diff(element, input, options) {
  return track(renderDiff(element, input, options));
}
async function renderDiff(element, input, { diffStyle = "split" } = {}) {
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
  if (files.length !== 1)
    throw Error("Each diff component requires one file pair.");
  // The bar above the viewer names the file; the viewer's own header would
  // repeat it with the path the patch was made from.
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
/* Components. A component is a named markup contract and the setup that
   turns an element carrying it into the rendered thing. define() records
   one; enhance() runs every registration over a page. A page renders by
   replacing #page-content, so setup runs again on every visit and rebuilds
   its state from planUI.prefs rather than holding it. */
const registry = new Map();
function define(name, { match, setup }) {
  registry.set(name, { match, setup });
}
/* One component's failure prints in place and leaves the rest of the page
   rendered. A setup that returns a promise is tracked, so the scroll
   position is restored only once its content has its height. */
function enhance(root) {
  for (const [name, { match, setup }] of registry) {
    for (const element of root.querySelectorAll(match)) {
      if (element.dataset.ready === name) continue;
      element.dataset.ready = name;
      try {
        const task = setup(element, { page, planUI: window.planUI });
        if (task instanceof Promise)
          track(task).catch((error) => failed(element, error));
      } catch (error) {
        failed(element, error);
      }
    }
  }
}
new ResizeObserver(() => {
  for (const instance of charts.values()) instance.resize();
}).observe($("page-content"));
let activeDrawing = null;
function drawingError(message) {
  $("drawing-error").textContent = message;
  $("drawing-error").hidden = !message;
  $("drawing-save").disabled = false;
}
function closeDrawing() {
  if (activeDrawing?.loadingTimer) clearTimeout(activeDrawing.loadingTimer);
  activeDrawing = null;
  $("drawing-frame").removeAttribute("srcdoc");
  if ($("drawing-dialog").open) $("drawing-dialog").close();
}
async function openDrawing(id, label, target, onSaved) {
  if (!editable || !online) return;
  const key = `${page.id}/${id}`;
  const previous = state.answers[key];
  let scene = null;
  if (previous?.kind === "drawing") {
    const response = await fetch(
      `${base}/api/drawing-scene/${encodeURIComponent(previous.sceneId)}`,
    );
    if (!response.ok) throw new Error("Could not load the saved drawing.");
    scene = await response.json();
  }
  const nonce = uuid();
  activeDrawing = { key, label, target, nonce, scene, onSaved, topic: page.id };
  activeDrawing.loadingTimer = setTimeout(() => {
    if (activeDrawing?.nonce === nonce)
      drawingError(
        "The drawing editor did not load. Check your connection and try again.",
      );
  }, 20000);
  $("drawing-title").textContent = label;
  drawingError("");
  $("drawing-save").disabled = true;
  $("drawing-frame").srcdoc = JSON.parse(
    $("drawing-editor-source").textContent,
  ).replace("__DRAWING_NONCE__", JSON.stringify(nonce));
  $("drawing-dialog").showModal();
}
$("drawing-cancel").onclick = closeDrawing;
$("drawing-dialog").addEventListener("close", () => {
  if (activeDrawing?.loadingTimer) clearTimeout(activeDrawing.loadingTimer);
  activeDrawing = null;
  $("drawing-frame").removeAttribute("srcdoc");
});
$("drawing-save").onclick = () => {
  if (!activeDrawing) return;
  $("drawing-save").disabled = true;
  $("drawing-frame").contentWindow.postMessage(
    { type: "save", nonce: activeDrawing.nonce },
    "*",
  );
};
addEventListener("message", async (event) => {
  const drawing = activeDrawing;
  if (
    !drawing ||
    event.source !== $("drawing-frame").contentWindow ||
    event.data?.nonce !== drawing.nonce
  )
    return;
  if (event.data.type === "ready") {
    clearTimeout(drawing.loadingTimer);
    drawing.loadingTimer = null;
    $("drawing-save").disabled = false;
    event.source.postMessage(
      { type: "init", nonce: drawing.nonce, scene: drawing.scene },
      "*",
    );
  } else if (event.data.type === "error") {
    drawingError(event.data.message || "Could not save the drawing.");
  } else if (event.data.type === "saved") {
    try {
      const [sceneResponse, previewResponse] = await Promise.all([
        fetch(`${base}/api/drawing-scene`, {
          method: "POST",
          body: JSON.stringify(event.data.scene),
        }),
        fetch(`${base}/api/upload`, { method: "POST", body: event.data.png }),
      ]);
      if (!sceneResponse.ok || !previewResponse.ok)
        throw new Error("Could not upload the drawing. Please try again.");
      const [scene, preview] = await Promise.all([
        sceneResponse.json(),
        previewResponse.json(),
      ]);
      if (activeDrawing !== drawing) return;
      const answer = {
        topic: drawing.topic,
        label: drawing.label,
        kind: "drawing",
        revision: plan.revision,
        sceneId: scene.id,
        previewId: preview.id,
        target: drawing.target,
      };
      state.answers[drawing.key] = answer;
      save();
      drawing.onSaved(answer);
      closeDrawing();
    } catch (error) {
      drawingError(error.message || "Could not save the drawing.");
    }
  }
});
window.planUI = {
  answer(id, text, label, target) {
    const key = page.id + "/" + id;
    if (text.trim())
      state.answers[key] = {
        topic: page.id,
        label: label || id,
        text,
        target,
        revision: plan.revision,
      };
    else delete state.answers[key];
    save();
  },
  drawing(id) {
    return state.answers[`${page.id}/${id}`];
  },
  draw: openDrawing,
  chart,
  define,
  diff,
  comment: (anchor, quote = "") => openNote(page.id, anchor, quote),
  enhance,
  prefs,
  mode,
};

/* Start */
document.title = plan.title;
// Agreed so far reads before the pages, Review comments after them, each
// behind a separator, and the drawer shows the same list as the sidebar.
function separator() {
  const divider = document.createElement("div");
  divider.className = "separator";
  divider.setAttribute("role", "separator");
  return divider;
}
for (const item of [
  pages.find((item) => item.id === "agreed"),
  ...pages.filter((item) => item.id !== "agreed"),
]) {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.page = item.id;
  button.textContent = item.title;
  $("navigation").append(button);
  if (item.id === "agreed") $("navigation").append(separator());
}
if (editable) {
  const review = document.createElement("button");
  review.type = "button";
  review.id = "review-row";
  review.dataset.page = "feedback";
  const label = document.createElement("span");
  label.textContent = "Review comments";
  const count = document.createElement("b");
  count.className = "count";
  count.hidden = true;
  review.append(label, count);
  $("navigation").append(separator(), review);
}
$("menu-button").addEventListener("click", () =>
  $("pages-dialog").open ? closeDrawer() : openDrawer(),
);
narrow.addEventListener("change", placeNavigation);
placeNavigation();
if (editable) initializeChecklists();
theme();
renderRevisions();
/* The first page renders once every component has registered. Component
   behaviors are bundled after this file and the plan's script is a module
   of its own, so both run while the document is still loading and both are
   done by DOMContentLoaded. */
function start() {
  let resume = null;
  try {
    resume = JSON.parse(sessionStorage.getItem(resumeKey));
    sessionStorage.removeItem(resumeKey);
  } catch {
    /* Start at the top. */
  }
  let place = null;
  try {
    place = usablePlace(
      JSON.parse(localStorage.getItem(placeKey)),
      plan.revision,
      [...pages.map((item) => item.id), ...(editable ? ["feedback"] : [])],
    );
  } catch {
    /* Start at the top. */
  }
  const opened = location.hash.slice(1) || query.get("target");
  show(
    resume?.first ? pages[0].id : location.hash.slice(1) || place?.page || "",
    query.get("target"),
    {
      keepScroll: false,
      push: false,
    },
  );
  // The browser restores the old scroll position after the reload; a new
  // revision starts at the top.
  if (resume?.first) setTimeout(() => scroller().scrollTo(0, 0), 60);
  else if (place?.top && !opened)
    // The page is short until the renderers finish, and the browser clamps a
    // scroll past the end, so the offset is restored after they settle.
    Promise.allSettled([...renders]).then(() =>
      scroller().scrollTo(0, place.top),
    );
  window.addEventListener("popstate", () => {
    const url = new URL(location.href);
    show(
      url.hash.slice(1) || plan.pages[0].id,
      url.searchParams.get("target"),
      { push: false },
    );
  });
  if (mode === "preview" && query.get("quote")) {
    const range = findText($("page-content"), query.get("quote"));
    if (range) {
      highlight("plan-preview", [range]);
      range.startContainer.parentElement?.scrollIntoView({ block: "center" });
    }
  }
  if (online && mode !== "preview") {
    poll();
    setInterval(poll, 1500);
    pollSessions();
    setInterval(pollSessions, 5000);
  } else review();
}
/* A module runs once the document is parsed, so readyState is "interactive"
   by this line and DOMContentLoaded is still ahead. That event is the point
   where every deferred script has run, this module's component blocks and
   the plan's module included. */
if (document.readyState === "complete") start();
else window.addEventListener("DOMContentLoaded", start, { once: true });
