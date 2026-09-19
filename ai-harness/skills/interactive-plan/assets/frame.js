const $ = (id) => document.getElementById(id);
const plan = JSON.parse($("plan-data").textContent);
const session = JSON.parse($("session-config").textContent);
const base = typeof session.base === "string" ? session.base : "";
const online =
  Boolean(session.sessionId) && /^https?:$/.test(location.protocol);
const mode = session.preview
  ? "preview"
  : session.readonly
    ? "readonly"
    : "live";
const editable = mode === "live";
document.documentElement.dataset.mode = mode;
const query = new URL(location.href).searchParams;
const agreements = plan.agreements || [];
const builtInAgreed = !plan.pages.some((item) => item.id === "agreed");
const pages = [
  ...plan.pages,
  ...(builtInAgreed ? [{ id: "agreed", title: "Agreed", html: "" }] : []),
];
const kindLabel = plan.kind === "plan" ? "Final plan" : "Exploration";
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
const sources = new WeakMap();
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
  $("theme").value = preferredTheme || "system";
  for (const chart of charts.values())
    chart.setOption({
      color: [color("--accent"), color("--muted")],
      ...chartTheme(chart.getOption()),
    });
  for (const viewer of diffs.values()) {
    viewer.setOptions({ ...viewer.options, theme: syntaxThemes[activeTheme] });
    viewer.rerender();
  }
  renderDiagrams($("page-content"));
  // A preview page reads the theme cookie when it loads.
  for (const frame of document.querySelectorAll(".agreement-preview iframe"))
    frame.contentWindow?.location.reload();
}
function disposeRenderers() {
  for (const chart of charts.values()) chart.dispose();
  charts.clear();
  clearDiffs();
}
// Page changes push history so the back button and a pasted hash both work;
// re-rendering the same page, restoring after a reload, and popstate itself
// leave history alone.
function show(id, targetId = null, { keepScroll = false, push = true } = {}) {
  const feedback = id === "feedback" && editable;
  $("reading").hidden = feedback;
  $("feedback").hidden = !feedback;
  if (!feedback) {
    page = pages.find((item) => item.id === id) || pages[0];
    disposeRenderers();
    $("page-title").textContent = page.title;
    $("page-content").innerHTML = page.html;
    choiceTargets($("page-content"), page.id);
    if (page.id === "agreed" && builtInAgreed) renderAgreements();
    else {
      restoreChoices();
      restoreAnswers();
      markNotes();
      enhance($("page-content"));
    }
    $("page-actions").hidden = page.id === "agreed" && builtInAgreed;
    window.dispatchEvent(
      new CustomEvent("plan:page", {
        detail: { page, element: $("page-content") },
      }),
    );
  }
  for (const button of $("navigation").querySelectorAll("[data-page]")) {
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
  if (!keepScroll) window.scrollTo(0, 0);
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
  if ($("pages-menu").querySelector("summary").offsetParent)
    $("pages-menu").open = false;
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
  tip.style.left = `${Math.min(event.pageX + 14, window.scrollX + innerWidth - width - 12)}px`;
  tip.style.top = `${event.pageY + 18}px`;
}
$("page-content").addEventListener("mousemove", showTip);
$("page-content").addEventListener("mouseleave", () => {
  $("note-tip").hidden = true;
  tipNotes = "";
});
// Any rendered diagram opens full size; the dialog closes on Escape or a
// click outside like the other dialogs.
$("page-content").addEventListener("click", (event) => {
  const svg = event.target.closest("[data-diagram] svg");
  if (!svg || event.target.closest("a")) return;
  const clone = svg.cloneNode(true);
  clone.style.width = `${svg.viewBox.baseVal.width}px`;
  clone.removeAttribute("width");
  $("diagram-dialog").replaceChildren(clone);
  $("diagram-dialog").showModal();
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
  $("note-anchor").textContent = anchor;
  $("note-quote").textContent = quote;
  $("note-quote").hidden = !quote;
  $("note-text").value =
    state.noteDrafts?.[noteDraftKey] ??
    (id ? state.notes.find((note) => note.id === id).text : "");
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
  const text = document.createElement("p");
  text.textContent =
    kind === "choice" || kind === "list" ? choiceText(item) : item.text;
  body.append(text);
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
  const item = $("navigation").querySelector('[data-page="feedback"]');
  if (!item) return;
  let mark = item.querySelector(".count");
  if (!count) {
    mark?.remove();
    return;
  }
  if (!mark) {
    mark = document.createElement("b");
    mark.className = "count";
    item.append(mark);
  }
  mark.textContent = String(count);
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
  const order = [
    ...pages,
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
  const sent = !unsent.count && state.submitted?.revision === plan.revision;
  $("submit").disabled = !unsent.count || !sendable;
  $("submit").textContent = unsent.count ? `Submit ${unsent.count}` : "Submit";
  // Accept plan takes the slot on an acceptable final plan; a sent round with
  // nothing new shows when it went instead of a disabled button.
  $("submit").hidden = !$("accept").hidden || (sent && !submissionError);
  $("submit-status").textContent =
    submissionError || (sent ? `Sent ${ago(state.submitted.at)}` : "");
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
    lines.push("", `${answer.label}`, answer.text);
  for (const note of notes)
    lines.push(
      "",
      note.anchor,
      ...(note.quote ? ["Selected passage: " + note.quote] : []),
      note.text,
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
    id: crypto.randomUUID(),
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
  try {
    sessionStorage.setItem(
      resumeKey,
      JSON.stringify({
        page: $("feedback").hidden ? page.id : "feedback",
        scrollY: window.scrollY,
      }),
    );
  } catch {
    /* Reload without restoring the position. */
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
  const silent = remote?.disconnected && remote.agentSeenAt;
  $("working-note").hidden = !silent;
  if (silent)
    $("working-note").textContent =
      `The agent has not checked in for ${since(remote.agentSeenAt)}.`;
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
      : remote?.disconnected
        ? "The agent has not checked in for a while. Feedback still saves."
        : "";
  if (newer && mode === "live") scheduleReload();
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
  if (["submitted", "working"].includes(entry.stage))
    return `Working · ${since(entry.updatedAt)}`;
  return "Live";
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
  for (const [heading, entries] of [
    ["Need you", need],
    ["Working", workingList],
    ["This one", mine],
  ]) {
    if (!entries.length) continue;
    const label = document.createElement("div");
    label.className = "group";
    label.textContent = heading;
    list.append(label);
    for (const entry of entries) {
      const row = document.createElement("button");
      row.type = "button";
      row.className =
        "session-row" +
        (entry.needsYou ? " need" : "") +
        (entry.id === session.sessionId ? " current" : "");
      const title = document.createElement("span");
      title.textContent = entry.title;
      const words = document.createElement("small");
      words.textContent = stateWords(entry);
      row.append(title, words);
      row.onclick = () => {
        if (entry.id === session.sessionId) toggleSidecar(false);
        else location.assign(entry.url);
      };
      list.append(row);
    }
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
  const menu = $("revision-menu");
  menu.replaceChildren();
  const heading = document.createElement("div");
  heading.className = "side-label";
  heading.textContent = "Revisions";
  menu.append(heading);
  for (const entry of entries) {
    const item = document.createElement("button");
    item.type = "button";
    item.className =
      "item" + (entry.revision === plan.revision ? " current" : "");
    item.setAttribute("role", "menuitem");
    const tick = document.createElement("span");
    tick.className = "tick";
    tick.textContent = entry.revision === plan.revision ? "✓" : "";
    const label = document.createElement("span");
    label.textContent = `Revision ${entry.revision}`;
    const time = document.createElement("small");
    time.textContent = entry.publishedAt ? ago(entry.publishedAt) : "";
    item.append(tick, label, time);
    item.onclick = () => {
      toggleRevisionMenu(false);
      if (entry.revision === plan.revision && mode === "live") return;
      location.assign(
        entry.revision === latest
          ? `${base}/`
          : entry.url || `${base}/r/${encodeURIComponent(entry.revision)}`,
      );
    };
    menu.append(item);
  }
  $("revision-text").textContent =
    `${kindLabel} · Revision ${plan.revision}${mode === "readonly" ? " · read-only" : ""}`;
  $("revision-back").hidden = mode !== "readonly";
  $("revision-back").href = `${base}/`;
}
function toggleRevisionMenu(open = $("revision-menu").hidden) {
  $("revision-menu").hidden = !open;
  $("revision").setAttribute("aria-expanded", String(open));
  if (open) $("revision-menu").querySelector("button")?.focus();
}
function toggleSidecar(open = $("sidecar").hidden) {
  if (open && $("bell").hidden) return;
  $("sidecar").hidden = !open;
  if (open) $("sidecar-close").focus();
}
function closeMenus() {
  toggleRevisionMenu(false);
  toggleSidecar(false);
  try {
    $("settings-menu").hidePopover();
  } catch {
    /* Already closed. */
  }
}

/* Choices, checklists, answers */
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
    area.value =
      state.answers[page.id + "/" + group.dataset.question]?.text ?? "";
    area.readOnly = !editable;
  });
}

$("note-form").onsubmit = (event) => {
  event.preventDefault();
  const text = $("note-text").value.trim();
  if (!text) return;
  const note = {
    ...noteContext,
    id: editing || crypto.randomUUID(),
    text,
    revision: plan.revision,
  };
  if (editing)
    state.notes = state.notes.map((item) =>
      item.id === editing ? note : item,
    );
  else state.notes.push(note);
  if (state.noteDrafts) delete state.noteDrafts[noteDraftKey];
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
    show(page.id, null, { keepScroll: false });
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
  if (close) $(close.dataset.close).close();
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
  if (!event.target.closest("#revision-menu")) toggleRevisionMenu(false);
  if (!event.target.closest("#sidecar")) toggleSidecar(false);
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
  if (area.value.trim())
    state.answers[key] = {
      topic: page.id,
      label: group.dataset.label || group.dataset.question,
      text: area.value,
      target: group.id,
      revision: plan.revision,
    };
  else delete state.answers[key];
  clearTimeout(answerTimer);
  answerTimer = setTimeout(save, 300);
});
document.addEventListener("selectionchange", () => {
  const selection = getSelection(),
    parent = selection?.anchorNode?.parentElement;
  selected = selection?.toString().trim() || "";
  selectedTarget = parent?.closest("#page-content [id]")?.id || null;
  $("quote").hidden = !(
    editable &&
    selected.length > 3 &&
    parent?.closest("#page-content") &&
    !document.querySelector("dialog[open]")
  );
});
$("quote").onpointerdown = (event) => event.preventDefault();
$("quote").onclick = () =>
  openNote(page.id, page.title, selected, null, null, selectedTarget);
$("page-comment").onclick = () => openNote(page.id, page.title);
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
$("theme").onchange = () => {
  preferredTheme = $("theme").value === "system" ? null : $("theme").value;
  activeTheme = preferredTheme || (systemTheme.matches ? "dark" : "light");
  try {
    if (/^https?:$/.test(location.protocol))
      document.cookie = `interactive-plan-theme=${preferredTheme || ""}; Path=/; SameSite=Strict; Max-Age=${preferredTheme ? 31536000 : 0}`;
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

/* Keys */
const interactiveSelector =
  "[data-choice] [data-value], [data-multiselect] input, [data-question] textarea, [data-comment], .link-btn, [data-diff-style], summary";
document.addEventListener("keydown", (event) => {
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
    const items = Array.from(
      $("page-content").querySelectorAll(interactiveSelector),
    ).filter((item) => item.offsetParent);
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
  } else if (key === "c" && editable && !$("reading").hidden)
    openNote(page.id, page.title);
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
  katex: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js",
  katexCss: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css",
  echarts: "https://cdn.jsdelivr.net/npm/echarts@6.0.0/dist/echarts.min.js",
};
const scripts = new Map();
let shikiTask,
  diffsTask,
  mermaidTask,
  diagramSequence = Promise.resolve();
const color = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();
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
async function renderCode(element) {
  const source = element.textContent;
  sources.set(element, source);
  try {
    shikiTask ||= import(libraries.shiki);
    const { codeToHtml } = await shikiTask;
    const html = await codeToHtml(source, {
      lang: element.dataset.language,
      themes: syntaxThemes,
      defaultColor: false,
    });
    if (element.isConnected) element.innerHTML = html;
  } catch (error) {
    failed(element, error);
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
          mermaidTask ||= import(libraries.mermaid);
          const { default: mermaid } = await mermaidTask;
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: "strict",
            theme: "base",
            themeVariables: {
              primaryColor: color("--ground"),
              primaryTextColor: color("--ink"),
              primaryBorderColor: color("--line-strong"),
              lineColor: color("--muted"),
              fontFamily: "sans-serif",
            },
            flowchart: {
              nodeSpacing: 28,
              rankSpacing: 36,
              padding: 12,
              subGraphTitleMargin: { top: 8, bottom: 8 },
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
        } catch (error) {
          failed(element, error);
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
    if (element.isConnected)
      window.katex.render(element.textContent, element, {
        throwOnError: true,
        displayMode: element.dataset.math !== "inline",
      });
  } catch (error) {
    failed(element, error);
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
    instance = window.echarts.init(element);
    charts.set(element, instance);
  }
  instance.setOption({
    backgroundColor: "transparent",
    color: [color("--accent"), color("--muted")],
    textStyle: { color: color("--ink") },
    ...options,
  });
  instance.setOption(chartTheme(options));
  return instance;
}
function clearDiffs() {
  for (const viewer of diffs.values()) viewer.cleanUp();
  diffs.clear();
}
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
function prototypeUrl(prototype) {
  if (online)
    return `${base}/r/${encodeURIComponent(plan.revision)}/prototype/${encodeURIComponent(prototype.id)}`;
  return URL.createObjectURL(new Blob([prototype.html], { type: "text/html" }));
}
function enhance(root) {
  root.querySelectorAll("[data-prototype]").forEach((mount) => {
    if (mount.querySelector("iframe")) return;
    const prototype = plan.prototypes?.find(
      (item) => item.id === mount.dataset.prototype,
    );
    if (!prototype) {
      failed(mount, Error("Prototype unavailable."));
      return;
    }
    const frame = document.createElement("iframe");
    frame.title = prototype.title;
    frame.className = "approved-prototype";
    frame.setAttribute("sandbox", "allow-scripts allow-forms allow-popups");
    frame.setAttribute("allowtransparency", "true");
    frame.style.height = `${prototype.height}px`;
    frame.srcdoc = prototype.html;
    const details = document.createElement("details");
    details.className = "prototype-source";
    const summary = document.createElement("summary");
    summary.textContent = "Source HTML, CSS, and JavaScript";
    details.append(summary);
    details.addEventListener("toggle", () => {
      if (!details.open || details.querySelector("[data-language]")) return;
      const source = document.createElement("div");
      source.dataset.language = "html";
      source.textContent = prototype.html;
      details.append(source);
      renderCode(source);
    });
    const open = document.createElement("a");
    open.textContent = "Open full size";
    open.target = "_blank";
    open.rel = "noopener";
    open.href = online ? prototypeUrl(prototype) : "#";
    if (!online)
      open.onclick = (event) => {
        event.preventDefault();
        window.open(prototypeUrl(prototype), "_blank", "noopener");
      };
    const source = linkButton("Source", () => {
      details.open = !details.open;
    });
    mount.append(frame);
    const wrapper = figure(mount, {
      title: prototype.title,
      actions: [source, document.createTextNode("·"), open],
      kind: "prototype",
    });
    wrapper.append(details);
  });
  root.querySelectorAll("[data-language]").forEach((element) => {
    if (element.dataset.file !== undefined || element.dataset.caption) {
      const meta = document.createElement("span");
      meta.textContent = element.dataset.language;
      figure(element, {
        title: element.dataset.file,
        meta,
        actions: [
          copyButton(() => sources.get(element) ?? element.textContent),
        ],
        caption: element.dataset.caption,
        kind: "code",
      });
    }
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
    try {
      const options = JSON.parse(element.textContent);
      element.textContent = "";
      if (element.dataset.title || element.dataset.caption)
        figure(element, {
          title: element.dataset.title,
          caption: element.dataset.caption,
          kind: "chart",
        });
      chart(element, options).catch((error) => {
        element.textContent = JSON.stringify(options, null, 2);
        failed(element, error);
      });
    } catch (error) {
      failed(element, error);
    }
  });
}
new ResizeObserver(() => {
  for (const instance of charts.values()) instance.resize();
}).observe($("page-content"));
window.planUI = {
  chart,
  diff,
  comment: (anchor, quote = "") =>
    openNote(page.id, anchor, quote, null, null, null),
  enhance,
  prefs,
  mode,
};

/* Start */
document.title = plan.title;
$("plan-title").textContent = plan.title;
for (const item of [
  ...pages.filter((item) => item.id !== "agreed"),
  pages.find((item) => item.id === "agreed"),
  ...(editable ? [{ id: "feedback", title: "Feedback" }] : []),
]) {
  if (item.id === "agreed") {
    const divider = document.createElement("div");
    divider.className = "separator";
    divider.setAttribute("role", "separator");
    $("navigation").append(divider);
  }
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.page = item.id;
  button.textContent = item.title;
  $("navigation").append(button);
}
const narrow = matchMedia("(max-width: 720px)");
const layoutMenu = () => {
  $("pages-menu").open = !narrow.matches;
};
narrow.addEventListener("change", layoutMenu);
layoutMenu();
if (editable) initializeChecklists();
theme();
renderRevisions();
let resume = null;
try {
  resume = JSON.parse(sessionStorage.getItem(resumeKey));
  sessionStorage.removeItem(resumeKey);
} catch {
  /* Start at the top. */
}
show(resume?.page || location.hash.slice(1), query.get("target"), {
  keepScroll: Boolean(resume),
  push: false,
});
window.addEventListener("popstate", () => {
  const url = new URL(location.href);
  show(url.hash.slice(1) || plan.pages[0].id, url.searchParams.get("target"), {
    push: false,
  });
});
if (resume) setTimeout(() => window.scrollTo(0, resume.scrollY), 60);
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
