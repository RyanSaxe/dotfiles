const $ = (id) => document.getElementById(id);
let plan = JSON.parse($("plan-data").textContent);
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
// A read-only revision keeps a Feedback page that lists what was sent on it.
const hasFeedbackPage = editable || mode === "readonly";
document.documentElement.dataset.mode = mode;
const query = new URL(location.href).searchParams;
let agreements = plan.agreements || [];
let pages = [{ id: "agreed", title: "Agreed so far", html: "" }, ...plan.pages];
let selectedTab = "current";
// The last revision this reader submitted, which keeps Current disabled until
// the next one arrives, and the past revision the left tab shows.
let submittedRevision = null;
let pastRevision = null;
// What was sent on each past revision the left tab has shown.
const sentByRevision = new Map();
const views = new Map([[plan.revision, { plan, agreements, pages }]]);
const pageSets = new Map();
const recordLoads = new Map();
let pageSetLoading = null;
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
// The activity card counts seconds in its first minute, so a fresh report
// visibly ticks up while the agent works.
function recently(value) {
  const ms = Date.now() - Date.parse(value);
  if (!Number.isFinite(ms)) return "";
  if (ms < 5000) return "just now";
  return ms < 60000 ? `${Math.round(ms / 1000)} s ago` : ago(value);
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
let placeStore = { tab: "current", past: null, places: {} };
try {
  placeStore = readPlaces(JSON.parse(localStorage.getItem(placeKey)));
} catch {
  /* Every revision then opens at its first page. */
}
const places = placeStore.places;
if (editable) pastRevision = placeStore.past;
if (editable && state.submitted?.revision === plan.revision) {
  submittedRevision = plan.revision;
  pastRevision = plan.revision;
  selectedTab = "past";
}
const known = {
  choices: new Set(),
  lists: new Set(),
  questions: new Set(),
  text: new Map(),
};
function indexPage(topic) {
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
for (const topic of plan.pages.filter((item) => !item.pending))
  indexPage(topic);
function rebuildKnown() {
  known.choices.clear();
  known.lists.clear();
  known.questions.clear();
  known.text.clear();
  for (const topic of pages.filter(
    (item) => item.id !== "agreed" && !item.pending,
  ))
    indexPage(topic);
}
function stale(kind, key, item) {
  if (kind === "note") {
    if (item.topic === "overall") return false;
    if (item.topic === "agreed")
      return Boolean(
        item.agreementId &&
        !agreements.some((entry) => entry.id === item.agreementId),
      );
    if (!known.text.has(item.topic))
      return !pages.some((entry) => entry.id === item.topic && entry.pending);
    return (
      Boolean(item.quote) &&
      !known.text.get(item.topic).includes(normalize(item.quote))
    );
  }
  if (pages.some((entry) => entry.id === item.topic && entry.pending))
    return false;
  if (kind === "answer") return !known.questions.has(key);
  if (kind === "list") return !known.lists.has(key);
  return !known.choices.has(key);
}

let page = pages[0],
  remote = null,
  connected = false,
  sessions = [],
  sessionOrder = [],
  editing = null,
  noteContext = null,
  selected = "",
  selectedTarget = null,
  submissionError = "",
  submissionInFlight = false,
  lastSubmission = null,
  lastSubmissionLoadedId = null,
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
  selectedTab === "current" &&
  remote?.current?.artifactId === plan.artifactId &&
  remote?.current?.revision === plan.revision;
const submittedCurrent = () =>
  editable &&
  (selectedTab === "past" ||
    state.submitted?.revision === plan.revision ||
    (current() && remote?.latestSubmissionRevision === plan.revision));
const feedbackEditable = () =>
  editable &&
  selectedTab === "current" &&
  !submissionInFlight &&
  !submittedCurrent();
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
  if (!editable || selectedTab !== "current") return;
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
/* Where you were in each revision, so switching tabs, picking a revision from
   the clock, a reload, and the bell's jump to another session and back all
   land on the page and scroll position you left. A revision you have not
   visited has no entry, which starts it at its first page. Only the live
   reader stores them, so a read-only page cannot overwrite its tabs. */
let placeTimer = 0;
function rememberPlace() {
  const pageId = $("reading").hidden ? "feedback" : page.id;
  const held =
    restoring?.revision === plan.revision && restoring.page === pageId;
  places[plan.revision] = {
    page: pageId,
    top: held ? restoring.top : Math.round(scroller().scrollTop),
  };
  if (!editable) return;
  clearTimeout(placeTimer);
  placeTimer = setTimeout(() => {
    try {
      localStorage.setItem(
        placeKey,
        JSON.stringify({ tab: selectedTab, past: pastRevision, places }),
      );
    } catch {
      /* Returning to the same place is a convenience, not a requirement. */
    }
  }, 250);
}
const placeIn = (revision, pageIds) => placeFor(places, revision, pageIds);
/* A page can still be loading, or its renderers can still change its height,
   when the reader returns to it, and the browser clamps the position
   meanwhile. Until the page settles, the position being restored stands in
   for the clamped one. */
let restoring = null;
function restoreScroll(top) {
  restoring = {
    revision: plan.revision,
    page: $("reading").hidden ? "feedback" : page.id,
    top,
  };
  settleScroll();
}
function settleScroll() {
  const target = restoring;
  if (!target) return;
  scroller().scrollTo(0, target.top);
  Promise.allSettled([...renders]).then(() => {
    if (restoring !== target) return;
    scroller().scrollTo(0, target.top);
    if ($("reading").hidden || !page.pending) restoring = null;
  });
}
document.addEventListener("scroll", rememberPlace, true);
function show(id, targetId = null, { keepScroll = false, push = true } = {}) {
  hideArrival();
  const resuming =
    restoring?.revision === plan.revision && restoring.page === id;
  if (!resuming) restoring = null;
  const top = scroller().scrollTop;
  const feedback = id === "feedback" && hasFeedbackPage;
  $("reading").hidden = feedback;
  $("feedback").hidden = !feedback;
  if (!feedback) {
    page = pages.find((item) => item.id === id) || pages[0];
    if (page.status === "ready" && page.pending)
      void loadPageRecord(plan.revision, page.id).catch(() => {});
    disposeRenderers();
    $("page-title").textContent = page.title;
    chooseBlock(null);
    $("page-content").dataset.pageId = page.id;
    $("page-content").dataset.revision = plan.revision;
    const [mark, label] = pendingState(page);
    $("page-content").innerHTML = page.pending
      ? `<div class="pending-page ${mark === "active" ? "working" : "queued"}"><span class="pending-state">${pageIndicator(mark).outerHTML}${label}</span><div class="pending-skeleton" aria-hidden="true"><i></i><i></i><i></i></div></div>`
      : page.html;
    if (!page.pending) {
      blockTargets($("page-content"), page.id);
      choiceTargets($("page-content"), page.id);
    }
    if (page.id === "agreed") renderAgreements();
    else if (!page.pending) {
      restoreChoices();
      restoreAnswers();
      markNotes();
      enhance($("page-content"));
    }
    renderSentPageComments();
    window.planUI.page = page;
    window.planUI.revision = plan.revision;
    window.dispatchEvent(
      new CustomEvent("plan:page", {
        detail: { page, element: $("page-content"), revision: plan.revision },
      }),
    );
    // Shiki, Mermaid and the charts all change a block's height after the
    // page renders, so the marks are placed again once they settle.
    Promise.allSettled([...renders]).then(placeMarks);
  }
  closeDrawer();
  for (const button of document.querySelectorAll("#page-list [data-page]")) {
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
  else if (resuming) settleScroll();
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
  if (!feedbackEditable()) return;
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
// In the live reader, a source's Open link loads its revision into the left
// tab at the page and block it names. A modified click still opens the
// read-only page in a new tab.
function openInTab(link, record) {
  if (!editable) return;
  link.addEventListener("click", (event) => {
    if (
      event.button ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    event.preventDefault();
    void openPast(record.revision, {
      pageId: record.topic,
      targetId: record.target,
    });
  });
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
    if (online) {
      open.href = recordUrl(first, "r");
      openInTab(open, first);
    } else {
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
    item.topic === "agreed" ? true : known.text.has(item.topic);
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
  $("overall-notes").replaceChildren(
    ...items.filter((entry) => entry.topic === "overall").map(itemCard),
  );
}
function sentEntries(submission) {
  if (!submission) return [];
  const groups = submission.groups || {};
  return [
    ...(groups.notes || []).map((note) => ({
      topic: note.topic,
      label: note.anchor || "Comment",
      text: note.text,
      quote: note.quote,
      images: (note.attachments || []).map((item) => item.id),
    })),
    ...Object.values(groups.choices || {}).map((choice) => ({
      topic: choice.topic,
      label: choice.label || "Choice",
      text: choiceText(choice),
    })),
    ...Object.values(groups.answers || {}).map((answer) => ({
      topic: answer.topic,
      label: answer.label || "Answer",
      text: answer.kind === "drawing" ? "Drawing attached" : answer.text,
      images: answer.kind === "drawing" ? [answer.previewId] : [],
    })),
  ];
}
function sentCard(entry) {
  const card = document.createElement("div");
  card.className = "sent-card";
  const label = document.createElement("small");
  label.textContent = `${pages.find((item) => item.id === entry.topic)?.title || entry.topic || "Overall"} · ${entry.label}`;
  const body = document.createElement("p");
  body.textContent = entry.text;
  card.append(label);
  if (entry.quote) {
    const quote = document.createElement("blockquote");
    quote.textContent = entry.quote;
    card.append(quote);
  }
  card.append(body);
  if (entry.images?.length) {
    const images = document.createElement("div");
    images.className = "sent-images";
    for (const id of entry.images) {
      const link = document.createElement("a");
      link.href = `${base}/api/upload/${encodeURIComponent(id)}`;
      link.target = "_blank";
      link.rel = "noopener";
      const thumbnail = document.createElement("img");
      thumbnail.src = link.href;
      thumbnail.alt = "Attached image";
      thumbnail.loading = "lazy";
      link.append(thumbnail);
      images.append(link);
    }
    card.append(images);
  }
  return card;
}
function renderSentPageComments() {
  const section = $("sent-page-comments");
  section.replaceChildren();
  const sent = shownSubmission();
  const entries = sent
    ? sentEntries(sent).filter((entry) => entry.topic === page.id)
    : [];
  section.hidden = !entries.length;
  if (!entries.length) return;
  const heading = document.createElement("h2");
  heading.textContent = "Your sent comments";
  section.append(heading, ...entries.map(sentCard));
}
let renderedSentKey = null;
function renderSentFeedback() {
  const sent = shownSubmission();
  // A past revision's submission may still be loading, which is not the same
  // as none having been sent.
  const loaded = mode === "readonly" || sentByRevision.has(plan.revision);
  const key = `${plan.revision}:${sent?.id || (loaded ? "none" : "")}`;
  if (renderedSentKey === key) return;
  renderedSentKey = key;
  const list = $("sent-feedback-list");
  list.replaceChildren();
  if (!sent) {
    if (loaded) {
      const empty = document.createElement("p");
      empty.className = "muted";
      empty.textContent = "No feedback was sent on this revision.";
      list.append(empty);
    }
    return;
  }
  const entries = sentEntries(sent);
  for (const entry of entries) list.append(sentCard(entry));
  if (!entries.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = sent.groups.alignUnflagged
      ? "Everything else looked good."
      : "No comments were sent.";
    list.append(empty);
  }
  renderSentPageComments();
}
// The submission sent on the revision on screen: the latest one, which the
// poll keeps, or one fetched for an older revision in the left tab.
function shownSubmission() {
  if (mode === "readonly" || lastSubmission?.revision === plan.revision)
    return lastSubmission;
  return sentByRevision.get(plan.revision) || null;
}
// A past revision shows what was sent on it, so its controls read from that
// revision's submission rather than from a draft.
function sentDraft(revision) {
  const draft = emptyDraft(revision);
  const sent =
    lastSubmission?.revision === revision
      ? lastSubmission
      : sentByRevision.get(revision);
  draft.choices = sent?.groups?.choices || {};
  draft.answers = sent?.groups?.answers || {};
  return draft;
}
async function loadPastSubmission(revision) {
  if (sentByRevision.has(revision) || lastSubmission?.revision === revision)
    return;
  const response = await fetch(
    `${base}/api/submission?revision=${encodeURIComponent(revision)}`,
  );
  if (!response.ok) return;
  const { submission } = await response.json();
  sentByRevision.set(revision, submission);
  const onScreen = selectedTab === "past" && plan.revision === revision;
  const draft = onScreen ? state : views.get(revision)?.draft;
  if (submission && draft && !draft.submitted) {
    draft.choices = submission.groups?.choices || {};
    draft.answers = submission.groups?.answers || {};
  }
  if (!onScreen) return;
  if (!$("reading").hidden)
    show(page.id, null, { keepScroll: true, push: false });
  renderSentFeedback();
  renderHistory();
}
async function loadSubmission() {
  const key =
    mode === "readonly"
      ? `revision:${plan.revision}`
      : remote?.latestSubmissionId;
  if (!key || key === lastSubmissionLoadedId) return;
  const route =
    mode === "readonly"
      ? `${base}/api/submission?revision=${encodeURIComponent(plan.revision)}`
      : `${base}/api/submission`;
  const response = await fetch(route);
  if (!response.ok) return;
  const { submission } = await response.json();
  if (mode !== "readonly" && remote?.latestSubmissionId !== key) return;
  if (mode !== "readonly" && submission && submission.id !== key) return;
  lastSubmission = submission;
  lastSubmissionLoadedId = key;
  // A read-only revision has no draft, so its controls show what was sent.
  if (mode === "readonly" && submission) {
    state.choices = submission.groups?.choices || {};
    state.answers = submission.groups?.answers || {};
    if (!$("reading").hidden)
      show(page.id, null, { keepScroll: true, push: false });
  }
  renderSentFeedback();
}
function badge(count) {
  const row = $("review-row");
  if (!row) return;
  const mark = row.querySelector(".count");
  mark.textContent = count ? `(${count})` : "";
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
    !submittedCurrent() &&
    !unsentCount &&
    ["ready", "updated"].includes(remote.stage)
  );
}
// Every reading page ends with where you came from and where to go next.
function renderFooter(feedback) {
  // Agreed so far leads the order, as it leads the sidebar.
  const order = [
    ...pages.filter((item) => item.id === "agreed"),
    ...pages.filter((item) => item.id !== "agreed"),
    ...(hasFeedbackPage ? [{ id: "feedback", title: "Feedback" }] : []),
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
  if (feedback) return;
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
        ? submittedCurrent() || !editable
          ? "Feedback →"
          : acceptable
            ? "Review and accept →"
            : "Review your feedback →"
        : `Next: ${next.title} →`,
  );
}
function renderActivity() {
  // A read-only revision shows what was sent on it, without agent activity.
  if (mode === "readonly") {
    $("agent-activity").hidden = true;
    $("sent-feedback").hidden = false;
    renderSentFeedback();
    return;
  }
  // The agent's progress belongs to the revision last submitted. An older
  // revision in the left tab shows only what was sent on it.
  const past = selectedTab === "past";
  const visible =
    (past && plan.revision === submittedRevision) || submissionInFlight;
  $("agent-activity").hidden = !visible;
  $("sent-feedback").hidden = !past || submissionInFlight;
  if (!visible) {
    if (past) renderSentFeedback();
    return;
  }
  const model = activityModel({
    remote,
    currentSet: pageSets.get(remote?.current?.revision),
    submittedRevision,
    inFlight: submissionInFlight,
  });
  const { slots, stopped } = model;
  const sentAt = lastSubmission?.receivedAt || state.submitted?.at;
  $("activity-elapsed").textContent = sentAt ? since(sentAt) : "";
  $("activity-title").textContent = model.title;
  $("activity-summary").textContent = model.summary;
  const signature = JSON.stringify([
    stopped,
    model.failed,
    model.track,
    slots.map(({ id, title, state }) => [id, title, state]),
  ]);
  const segments = $("activity-segments");
  const rows = $("activity-pages");
  if (rows.dataset.signature !== signature) {
    rows.dataset.signature = signature;
    segments.replaceChildren();
    rows.replaceChildren();
    if (model.track) {
      const track = document.createElement("i");
      track.className = `track ${model.track}`;
      segments.append(track);
    }
    for (const slot of slots) {
      const item = document.createElement("i");
      item.className =
        slot.state === "ready"
          ? "done"
          : slot.state === "active" && !stopped
            ? "now"
            : "";
      segments.append(item);
      const row = document.createElement("div");
      row.className = "activity-page";
      const name = document.createElement("span");
      name.textContent = slot.title;
      const label = document.createElement("small");
      label.textContent =
        slot.state === "ready"
          ? "Ready"
          : slot.state === "active"
            ? stopped
              ? model.failed
                ? "Stopped"
                : "Paused"
              : "Working"
            : "Queued";
      const mark = pageIndicator(pageStatus({ status: slot.state }));
      if (stopped) mark.classList.add("stopped");
      row.append(mark, name, label);
      rows.append(row);
    }
  }
  const { footer } = model;
  const report = $("activity-report");
  // The mark is replaced only when its state changes, so polling does not
  // restart its breathing.
  const mark = pageIndicator(
    footer.mark === "stopped" ? "active" : footer.mark,
  );
  if (footer.mark === "stopped") mark.classList.add("stopped");
  const old = report.querySelector(".page-activity");
  if (old?.className !== mark.className)
    old ? old.replaceWith(mark) : report.prepend(mark);
  $("activity-report-text").textContent = footer.at
    ? `${footer.text} ${recently(footer.at)}`
    : footer.text;
  report.classList.toggle("late", Boolean(footer.late));
  if (!submissionInFlight) renderSentFeedback();
}
// Every page of a past revision, its Feedback page included, names the
// revision. Current never has the strip.
function renderHistory() {
  const old = mode === "readonly";
  const past = selectedTab === "past";
  const strip = $("history-strip");
  strip.hidden = !(old || past);
  if (strip.hidden) return;
  const label = $("history-label");
  if (old && session.closed) label.textContent = "This plan is closed";
  else {
    const name = document.createElement("b");
    name.textContent = `Revision ${plan.revision}`;
    label.replaceChildren(name);
    if (past || shownSubmission()) {
      const meta = document.createElement("span");
      meta.className = "meta";
      meta.textContent = " · Feedback sent";
      label.append(meta);
    }
  }
  const button = $("history-return");
  button.hidden = old ? session.closed : !currentAvailable();
  button.textContent = "Back to current";
  button.onclick = old
    ? () => location.assign(`${base}/`)
    : () => switchTab("current");
}
function review() {
  const unsent = unsentItems(state);
  const sent = selectedTab === "past" || mode === "readonly";
  const locked = sent || submissionInFlight || submittedCurrent();
  $("draft-head").hidden = unsent.count === 0;
  $("draft-count").textContent = `${unsent.count} to send`;
  badge(locked ? 0 : unsent.count);
  const reviewLabel = $("review-row")?.querySelector("span");
  if (reviewLabel) reviewLabel.textContent = sent ? "Feedback" : "Review";
  $("feedback-title").textContent = sent
    ? "Feedback"
    : submissionInFlight
      ? "Sending feedback"
      : "Review";
  $("feedback-review").hidden = locked;
  renderActivity();
  renderHistory();
  $("submit-error").hidden = !submissionError;
  $("submit-error").textContent = submissionError;
  $("save-error").hidden = !submissionError || $("reading").hidden;
  $("save-error-text").textContent = submissionError;
  $("overall-note").disabled = locked;
  $("align-unflagged").checked = state.alignUnflagged;
  $("align-unflagged").disabled = locked;
  if (locked)
    $("page-content")
      .querySelectorAll(
        "[data-choice] [data-value], [data-multiselect] input, [data-question] textarea, [data-answer], [data-edit], [data-drawing-question] [data-draw], [data-comment]",
      )
      .forEach((control) => {
        if (control.tagName === "TEXTAREA") control.readOnly = true;
        else control.disabled = true;
      });
  commentTarget();
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
  // The header button always acts on Current. From a past revision it submits
  // Current's draft, and once Current's revision is sent it opens that
  // revision's Feedback.
  const forCurrent = selectedTab === "past" && currentAvailable();
  const draft = forCurrent ? currentDraft() : state;
  const pending = forCurrent ? unsentItems(draft) : unsent;
  const kind = forCurrent
    ? views.get(remote.current.revision).plan.kind
    : plan.kind;
  const opensFeedback = sent && !forCurrent;
  const onSentFeedback =
    $("reading").hidden &&
    (mode === "readonly" || plan.revision === submittedRevision);
  const sendable =
    connected &&
    !remote?.pageRound &&
    (forCurrent || (current() && feedbackEditable()));
  const waitingForPages = Boolean(remote?.pageRound);
  const hasFeedback =
    pending.count > 0 || (kind === "exploration" && draft.alignUnflagged);
  $("submit").disabled =
    submissionInFlight ||
    (opensFeedback
      ? onSentFeedback
      : waitingForPages || !hasFeedback || !sendable);
  $("submit").textContent = submissionInFlight
    ? "Sending"
    : opensFeedback
      ? "Feedback"
      : pending.count
        ? `Submit (${pending.count})`
        : "Submit";
  $("submit").classList.toggle("primary", !opensFeedback && !waitingForPages);
  // Accept plan uses the same slot when a final plan has no unsent feedback.
  $("submit").hidden = !$("accept").hidden;
  status();
}
function feedbackText() {
  const { notes, choices, answers } = unsentItems(state);
  const lines = [
    `Feedback: ${plan.title}`,
    `Artifact ${plan.artifactId}, revision ${plan.revision}`,
    "Feedback only. No implementation approval.",
    `Everything else looks good: ${state.alignUnflagged ? "yes" : "no"}.`,
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

/* A published page is fetched once. Polls only update its place in the list. */
async function loadPageRecord(revision, id) {
  const view = views.get(revision);
  const manifest = pageSets.get(revision);
  const slot = manifest?.pages.find((item) => item.id === id);
  if (!view || !slot?.version) return;
  const key = `${revision}/${id}/${slot.version}`;
  if (recordLoads.has(key)) return recordLoads.get(key);
  const task = (async () => {
    const url = `${base}/api/page?revision=${encodeURIComponent(revision)}&id=${encodeURIComponent(id)}&version=${slot.version}`;
    const response = await fetch(url);
    if (!response.ok) throw Error("Could not load this page.");
    const record = await response.json();
    if (record.revision !== revision || record.page.id !== id)
      throw Error("Wrong page record.");
    const entry = view.pages.find((item) => item.id === id);
    if (id === "agreed") {
      view.agreements = record.page.agreements;
      if (plan.revision === revision) agreements = view.agreements;
    } else {
      let setup = null;
      if (record.page.jsText) {
        const blob = new Blob([record.page.jsText], {
          type: "text/javascript",
        });
        const moduleUrl = URL.createObjectURL(blob);
        try {
          ({ setup } = await import(moduleUrl));
          if (typeof setup !== "function")
            throw Error("Page setup is unavailable.");
        } finally {
          URL.revokeObjectURL(moduleUrl);
        }
      }
      entry.html = record.page.html;
      entry.loaded = true;
      entry.pending = false;
      indexPage(entry);
      view.plan.prototypes ||= [];
      view.plan.prototypes.push(...(record.page.prototypes || []));
      if (record.page.cssText) {
        const style = document.createElement("style");
        style.textContent = `@layer plan { @scope (#page-content[data-page-id="${id}"][data-revision="${revision}"]) { ${record.page.cssText} } }`;
        document.head.append(style);
      }
      if (setup)
        window.addEventListener("plan:page", ({ detail }) => {
          if (detail.page.id === id && detail.revision === revision)
            setup(detail.element, window.planUI);
        });
    }
    if (
      id !== "agreed" &&
      plan.revision === revision &&
      page.id === id &&
      !$("reading").hidden
    ) {
      const top = scroller().scrollTop;
      const focused = document.activeElement;
      show(id, null, { keepScroll: true, push: false });
      if (focused?.isConnected) focused.focus({ preventScroll: true });
      if (!restoring) scroller().scrollTo(0, top);
    }
    return record;
  })().catch((error) => {
    recordLoads.delete(key);
    if (plan.revision === revision && page.id === id && !$("reading").hidden) {
      $("page-content").innerHTML =
        `<div class="page-load-error" role="alert"><p>Could not load this page.</p><button class="btn" type="button">Retry</button></div>`;
      $("page-content").querySelector("button").onclick = () =>
        loadPageRecord(revision, id).catch(() => {});
    }
    throw error;
  });
  recordLoads.set(key, task);
  return task;
}
function pageStatus(item) {
  return item.status === "ready" || (!item.status && !item.pending)
    ? "complete"
    : item.status === "active"
      ? "active"
      : "queued";
}
// A ready page whose record has not arrived yet shows as loading, not queued.
function pendingState(item) {
  if (item.status === "ready") return ["active", "Loading this page"];
  return item.working
    ? ["active", "Preparing this page"]
    : ["queued", "Waiting to start"];
}
function reconcilePages(view, manifest) {
  for (const slot of manifest.pages) {
    let entry = view.pages.find((item) => item.id === slot.id);
    if (!entry) {
      entry = { id: slot.id, title: slot.title, html: "", pending: true };
      view.pages.push(entry);
    }
    if (entry.loaded === undefined) entry.loaded = !entry.pending;
    entry.title = slot.title;
    entry.status = slot.state;
    entry.working = slot.state === "active";
    if (slot.state !== "ready") entry.pending = true;
    if (slot.state === "ready" && !entry.loaded && slot.id !== "agreed")
      entry.pending = true;
  }
  view.pages = manifest.pages.map((slot) =>
    view.pages.find((item) => item.id === slot.id),
  );
  view.plan.pages = view.pages.filter((item) => item.id !== "agreed");
  if (plan.revision === view.plan.revision) pages = view.pages;
}
async function syncPageSet() {
  const revision = remote?.current?.revision;
  if (!revision || !remote.pageSetGeneration) return;
  if (pageSetLoading) return pageSetLoading;
  const previous = pageSets.get(revision);
  if (previous?.generation === remote.pageSetGeneration) return;
  pageSetLoading = (async () => {
    const response = await fetch(
      `${base}/api/page-set?revision=${encodeURIComponent(revision)}`,
    );
    if (!response.ok) throw Error("Could not load page list.");
    const manifest = await response.json();
    let view = views.get(revision);
    if (!view) {
      const nextPlan = {
        artifactId: remote.current.artifactId,
        revision,
        kind: remote.current.kind,
        title: remote.current.title,
        pages: [],
        agreements: [],
      };
      view = { plan: nextPlan, agreements: [], pages: [] };
      views.set(revision, view);
    }
    const wasReady = new Set(
      previous?.pages
        .filter((item) => item.state === "ready")
        .map((item) => item.id),
    );
    pageSets.set(revision, manifest);
    reconcilePages(view, manifest);
    try {
      await loadPageRecord(revision, "agreed");
    } catch (error) {
      if (previous) pageSets.set(revision, previous);
      else pageSets.delete(revision);
      throw error;
    }
    if (selectedTab === "current" && plan.revision === revision) {
      updateNavigation();
      const selected = manifest.pages.find((item) => item.id === page.id);
      if (selected?.state === "ready" && page.pending)
        void loadPageRecord(revision, page.id).catch(() => {});
      else if (selected && page.pending && !$("reading").hidden) {
        const [mark, label] = pendingState(page);
        $("page-content")
          .querySelector(".pending-state")
          ?.replaceChildren(
            pageIndicator(mark),
            document.createTextNode(label),
          );
      }
      announceArrivals([...wasReady]);
    } else updateNavigation();
  })().finally(() => {
    pageSetLoading = null;
  });
  return pageSetLoading;
}
// A revision published before page sets existed has none. It opens on its
// own read-only page instead, without asking again on every poll.
const missingSets = new Set();
const pastLoads = new Map();
// Load a past revision's page list and Agreed into a view the left tab can
// show. Resolves false for a revision that has no page set.
function loadPastView(revision) {
  if (!revision) return Promise.resolve(false);
  if (views.has(revision)) return Promise.resolve(true);
  if (missingSets.has(revision)) return Promise.resolve(false);
  if (pastLoads.has(revision)) return pastLoads.get(revision);
  const task = (async () => {
    const response = await fetch(
      `${base}/api/page-set?revision=${encodeURIComponent(revision)}`,
    );
    if (response.status === 404) {
      missingSets.add(revision);
      return false;
    }
    if (!response.ok) throw Error("Could not load that revision's pages.");
    const manifest = await response.json();
    const entry = remote?.revisions?.find((item) => item.revision === revision);
    const oldPlan = {
      artifactId: entry?.artifactId || remote.current.artifactId,
      revision,
      kind: entry?.kind || remote.current.kind,
      title: entry?.title || remote.current.title,
      pages: [],
      agreements: [],
    };
    const view = { plan: oldPlan, agreements: [], pages: [] };
    views.set(revision, view);
    pageSets.set(revision, manifest);
    reconcilePages(view, manifest);
    try {
      await loadPageRecord(revision, "agreed");
    } catch (error) {
      views.delete(revision);
      pageSets.delete(revision);
      throw error;
    }
    updateNavigation();
    return true;
  })().finally(() => {
    pastLoads.delete(revision);
  });
  pastLoads.set(revision, task);
  return task;
}
// The clock and an agreement's Open link load a past revision into the left
// tab. A revision from before page sets opens on its own read-only page.
async function openPast(revision, { pageId = null, targetId = null } = {}) {
  const loaded = await loadPastView(revision).catch(() => false);
  if (!loaded) {
    location.assign(`${base}/r/${encodeURIComponent(revision)}`);
    return;
  }
  pastRevision = revision;
  if (pageId) places[revision] = { page: pageId, top: 0 };
  switchTab("past", targetId);
}
// Current's draft while a past revision is on screen: the one set aside when
// the reader left Current, or the saved one.
function currentDraft() {
  const view = views.get(remote?.current?.revision);
  if (view?.draft) return view.draft;
  try {
    return loadDraft(
      JSON.parse(localStorage.getItem(storageKey)),
      remote.current.revision,
    );
  } catch {
    return emptyDraft(remote.current.revision);
  }
}
// Each tab reopens its revision at the page and scroll position the reader
// left, or at Agreed on a first visit.
function switchTab(tab, targetId = null) {
  if (tab === "current" && !currentAvailable()) return;
  if (tab === "past" && !pastAvailable()) return;
  const revision = tab === "current" ? remote.current.revision : pastRevision;
  const view = views.get(revision);
  views.get(plan.revision).draft = state;
  selectedTab = tab;
  plan = view.plan;
  document.title = plan.title;
  agreements = view.agreements;
  pages = view.pages;
  let saved = null;
  try {
    saved = JSON.parse(localStorage.getItem(storageKey));
  } catch {
    /* The in-memory draft and export remain available. */
  }
  state =
    view.draft ||
    (tab === "past" ? sentDraft(revision) : loadDraft(saved, revision));
  rebuildKnown();
  if (tab === "current") initializeChecklists();
  page = pages[0];
  renderedFeedback = null;
  updateNavigation(true);
  const place = placeIn(revision, [
    ...pages.map((item) => item.id),
    "feedback",
  ]);
  show(place?.page || "agreed", targetId);
  if (place?.top && !targetId) restoreScroll(place.top);
  if (tab === "past") void loadPastSubmission(revision).catch(() => {});
  renderRevisions();
}
const currentAvailable = () =>
  Boolean(
    remote?.current &&
    remote.current.revision !== submittedRevision &&
    views.has(remote.current.revision),
  );
const pastAvailable = () => Boolean(pastRevision && views.has(pastRevision));
function status() {
  const stage = !connected ? "disconnected" : remote?.stage || "ready";
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
  if (remote?.dismissedAt && mode === "live") location.reload();
}
async function poll() {
  try {
    const response = await fetch(`${base}/api/status`);
    if (!response.ok) throw Error();
    const result = await response.json();
    if (result.sessionId !== session.sessionId) throw Error("Wrong session");
    remote = result;
    connected = true;
    if (editable && !submittedRevision)
      submittedRevision =
        state.submitted?.revision || remote.latestSubmissionRevision;
    if (editable && !pastRevision) pastRevision = submittedRevision || null;
    // A read-only page stays on its own revision. A failed page-set fetch is
    // retried on the next poll and does not mean the hub is unreachable.
    if (editable) {
      await syncPageSet().catch(() => {});
      await loadPastView(pastRevision).catch(() => {});
    }
    // Current's revision was sent, here or in another browser: the left tab
    // takes it, on its Feedback page, where the agent's progress shows.
    if (
      selectedTab === "current" &&
      submittedRevision === plan.revision &&
      remote.latestSubmissionRevision === plan.revision
    ) {
      pastRevision = plan.revision;
      places[plan.revision] = { page: "feedback", top: 0 };
      switchTab("past");
    }
    void loadSubmission().catch(() => {});
    if (
      state.pending?.event?.id === remote.latestSubmissionId &&
      remote.latestSubmissionRevision === plan.revision &&
      state.submitted?.id !== remote.latestSubmissionId
    ) {
      markSent(state, remote.latestSubmissionId, new Date().toISOString());
      persist();
    }
  } catch {
    connected = false;
  }
  renderRevisions();
  updateNavigation();
  renderRound();
  review();
}
// The Pages heading in the sidebar and in the phone drawer shows the page
// round's status. The text stays while the status fades out.
function renderRound() {
  const model = editable ? roundModel({ remote }) : null;
  for (const status of document.querySelectorAll("[data-round]")) {
    status.classList.toggle("idle", !model);
    status.classList.toggle("late", Boolean(model?.late));
    if (model) status.lastElementChild.textContent = model.text;
  }
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
  if (entry.pageRound)
    return `Working · ${entry.pageRound.ready} pages readable`;
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
let renderedRevisions = "";
function renderRevisions() {
  const entries = (
    remote?.revisions?.length
      ? remote.revisions
      : [{ revision: plan.revision, publishedAt: null }]
  )
    .slice()
    .reverse();
  if (
    remote?.pageRound &&
    !entries.some((entry) => entry.revision === remote.current.revision)
  )
    entries.unshift(remote.current);
  const latest = remote?.current?.revision ?? entries[0].revision;
  const signature = JSON.stringify([
    latest,
    entries.map((entry) => [entry.revision, entry.publishedAt]),
    plan.revision,
    mode,
    selectedTab,
    submittedRevision,
  ]);
  if (signature === renderedRevisions) return;
  renderedRevisions = signature;
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
    const status = document.createElement("small");
    status.textContent =
      entry.revision === latest && latest !== submittedRevision
        ? "Current"
        : "Feedback sent";
    label.append(document.createElement("br"), status);
    const time = document.createElement("small");
    time.textContent = entry.publishedAt ? ago(entry.publishedAt) : "";
    row.append(tick, label, time);
    // The live reader loads a past revision into the left tab. A read-only
    // page has no tabs, so it opens the revision's own page.
    row.onclick = () => {
      toggleRevisionMenu(false);
      if (here) return;
      if (mode !== "live")
        location.assign(
          entry.revision === latest
            ? `${base}/`
            : entry.url || `${base}/r/${encodeURIComponent(entry.revision)}`,
        );
      else if (entry.revision === latest && currentAvailable())
        switchTab("current");
      else void openPast(entry.revision);
    };
    list.append(row);
  }
  // An older revision is read-only, and the clock alone does not say which
  // one you are on, so a strip under the header names it. A closed session
  // is read-only on its current revision, and there is nowhere to go back
  // to, so the strip says that instead and drops the link.
  // The plan's name lives in this dialog, because the frame shows it nowhere
  // else.
  $("revision-plan").textContent = plan.title;
  const older = mode === "readonly" || selectedTab === "past";
  $("revision").classList.toggle("older", older);
  renderHistory();
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
  for (const topic of plan.pages.filter((item) => !item.pending)) {
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
  if (!feedbackEditable()) return;
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
$("align-unflagged").onchange = (event) => {
  if (!feedbackEditable()) return;
  state.alignUnflagged = event.target.checked;
  save();
};
$("submit").onclick = async () => {
  if (selectedTab === "past") {
    // Current's revision was already sent, so the button opens its Feedback.
    if (!currentAvailable()) {
      places[submittedRevision] = { page: "feedback", top: 0 };
      void openPast(submittedRevision);
      return;
    }
    switchTab("current");
  }
  if (remote?.pageRound) return;
  if (
    !feedbackEditable() ||
    (unsentItems(state).count === 0 &&
      (plan.kind !== "exploration" || !state.alignUnflagged))
  )
    return;
  submissionError = "";
  const origin = {
    page: $("reading").hidden ? "feedback" : page.id,
    top: scroller().scrollTop,
  };
  submissionInFlight = true;
  show("feedback");
  try {
    await Promise.all(
      pages
        .filter((item) => item.id !== "agreed" && item.pending)
        .map((item) => loadPageRecord(plan.revision, item.id)),
    );
    initializeChecklists();
    const groups = submissionGroups(state);
    const snapshot = JSON.stringify(groups);
    if (state.pending?.snapshot !== snapshot)
      state.pending = {
        snapshot,
        event: envelope("feedback-only", feedbackText(), { groups }),
      };
    persist();
    const result = await send(state.pending.event);
    markSent(state, result.id, new Date().toISOString());
    submissionInFlight = false;
    save();
    submittedRevision = plan.revision;
    pastRevision = plan.revision;
    places[plan.revision] = { page: "feedback", top: 0 };
    switchTab("past");
    void loadSubmission().catch(() => {});
  } catch (error) {
    submissionInFlight = false;
    submissionError = submittedCurrent()
      ? ""
      : error instanceof TypeError
        ? "Could not reach the hub. Your comments are saved here. Try Submit again."
        : error.message;
    show(origin.page);
    scroller().scrollTo(0, origin.top);
    review();
  }
};
$("save-error-dismiss").onclick = () => {
  submissionError = "";
  review();
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
  $("accept-guidance").value = state.acceptGuidance || "";
  $("accept-error").textContent = "";
  $("accept-dialog").showModal();
}
$("accept").onclick = openAccept;
$("accept-guidance").oninput = (event) => {
  state.acceptGuidance = event.target.value;
  persist();
};
document.querySelectorAll("[data-accept-mode]").forEach(
  (button) =>
    (button.onclick = async () => {
      const mode = button.dataset.acceptMode;
      const guidance =
        mode === "implement" ? $("accept-guidance").value.trim() : "";
      const action =
        mode === "implement"
          ? "Start implementation of this plan."
          : "Save for later. Do not start implementation.";
      const text = `Accept ${plan.artifactId} revision ${plan.revision}. ${action}${guidance ? `\n\nImplementation guidance:\n${guidance}` : ""}`;
      if (
        state.acceptance?.mode !== mode ||
        (state.acceptance?.guidance || "") !== guidance
      )
        state.acceptance = envelope("accept-plan", text, {
          mode,
          ...(guidance ? { guidance } : {}),
        });
      persist();
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
  const tab = event.target.closest("button[data-tab]");
  if (tab) {
    switchTab(tab.dataset.tab);
    return;
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
  if (!feedbackEditable()) return;
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
  if (!feedbackEditable()) return;
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
  if (!feedbackEditable()) return;
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
  const usable = editable && !page.pending && !$("reading").hidden;
  button.hidden = !usable;
  if (!usable) return;
  button.disabled = !feedbackEditable();
  if (button.disabled) {
    button.textContent = "Comments sent";
    return;
  }
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
  if (!feedbackEditable() || page.pending) return;
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
  if (!feedbackEditable() || page.pending) return;
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
    feedbackEditable()
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
  } else if (key === "c" && feedbackEditable() && !$("reading").hidden)
    commentOnTarget();
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
  if (!feedbackEditable() || !online) return;
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
    if (!feedbackEditable()) return;
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
  page: null,
};

/* Start */
document.title = plan.title;
// Agreed so far reads before the pages, Review or Feedback after them, each
// behind a separator, and the drawer shows the same list as the sidebar.
function separator() {
  const divider = document.createElement("div");
  divider.className = "separator";
  divider.setAttribute("role", "separator");
  return divider;
}
function pageIndicator(state) {
  const indicator = document.createElement("span");
  indicator.className = `page-activity ${state}`;
  indicator.setAttribute("aria-hidden", "true");
  if (state !== "active")
    indicator.innerHTML =
      state === "complete"
        ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 4.5 4.5L19 7"/></svg>'
        : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>';
  return indicator;
}
function addPageButton(item) {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.page = item.id;
  const title = document.createElement("span");
  title.textContent = item.title;
  // A long name ends in an ellipsis, so the full name is a tooltip.
  title.title = item.title;
  button.append(title);
  if (item.status !== "ready" && item.pending) {
    button.classList.add("pending");
    button.setAttribute(
      "aria-label",
      `${item.title}, ${item.working ? "being prepared" : "queued"}`,
    );
    button.append(pageIndicator(item.working ? "active" : "queued"));
  } else {
    button.append(pageIndicator("complete"));
  }
  $("page-list").append(button);
}
const tabs = document.createElement("div");
tabs.className = "page-tabs";
tabs.setAttribute("role", "tablist");
tabs.setAttribute("aria-label", "Page versions");
// The left tab holds the past revision on screen, so the tabs read in time
// order.
for (const tab of ["past", "current"]) {
  const button = document.createElement("button");
  button.type = "button";
  button.id = `${tab}-tab`;
  button.dataset.tab = tab;
  button.setAttribute("role", "tab");
  button.textContent = tab === "current" ? "Current" : "Previous";
  tabs.append(button);
}
// A read-only page shows one revision, so there is nothing to switch to.
tabs.hidden = !editable;
const pageList = document.createElement("div");
pageList.id = "page-list";
$("navigation").append(tabs, pageList);
function updateNavigation(force = false) {
  const currentSet = pageSets.get(remote?.current?.revision);
  const readyPages = currentAvailable()
    ? currentSet?.pages.filter((item) => item.state === "ready").length || 0
    : selectedTab === "current"
      ? pages.filter((item) => !item.pending).length
      : 0;
  $("page-count").hidden = !readyPages;
  $("page-count").textContent = readyPages;
  $("menu-button").classList.toggle("need", readyPages > 0);
  $("menu-button").setAttribute(
    "aria-label",
    `Pages, ${plural(readyPages, "current page")} ready to read`,
  );
  $("current-tab").disabled = Boolean(submittedRevision) && !currentAvailable();
  $("past-tab").disabled = !pastAvailable();
  $("past-tab").textContent = pastRevision
    ? `Revision ${pastRevision}`
    : "Previous";
  for (const tab of ["past", "current"])
    $(`${tab}-tab`).setAttribute("aria-selected", String(selectedTab === tab));
  let count = $("current-tab").querySelector(".tab-count");
  if (!count) {
    count = document.createElement("span");
    count.className = "tab-count";
    $("current-tab").append(count);
  }
  count.textContent = `(${readyPages})`;
  count.hidden = !readyPages || selectedTab === "current";
  if (
    force ||
    pageList.dataset.revision !== plan.revision ||
    pageList.dataset.tab !== selectedTab
  ) {
    pageList.replaceChildren();
    addPageButton(pages[0]);
    pageList.append(separator());
    for (const item of pages.slice(1)) addPageButton(item);
    if (hasFeedbackPage) {
      const review = document.createElement("button");
      review.type = "button";
      review.id = "review-row";
      review.dataset.page = "feedback";
      const label = document.createElement("span");
      label.textContent =
        editable && selectedTab === "current" ? "Review" : "Feedback";
      const total = document.createElement("b");
      total.className = "count";
      total.hidden = true;
      review.append(label, total);
      pageList.append(separator(), review);
    }
    pageList.dataset.revision = plan.revision;
    pageList.dataset.tab = selectedTab;
  }
  for (const item of pages) {
    const button = [...pageList.querySelectorAll("[data-page]")].find(
      (node) => node.dataset.page === item.id,
    );
    if (!button) continue;
    button.classList.toggle("pending", pageStatus(item) !== "complete");
    const old = button.querySelector(".page-activity");
    const next = pageIndicator(pageStatus(item));
    if (old?.className !== next.className) old?.replaceWith(next);
    button.setAttribute(
      "aria-label",
      `${item.title}, ${pageStatus(item) === "complete" ? "ready" : item.working ? "working" : "queued"}`,
    );
  }
  for (const button of pageList.querySelectorAll("[data-page]"))
    if (button.dataset.page === ($("reading").hidden ? "feedback" : page.id))
      button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
}
updateNavigation(true);
$("menu-button").addEventListener("click", () =>
  $("pages-dialog").open ? closeDrawer() : openDrawer(),
);
$("feedback-pages").addEventListener("click", openDrawer);
let arrivalTimer;
let arrivalPage = null;
function hideArrival() {
  clearTimeout(arrivalTimer);
  $("page-arrival").hidden = true;
}
function announceArrivals(previousReady) {
  if (!narrow.matches || !Array.isArray(previousReady)) return;
  const seen = new Set(previousReady);
  const arrived = pages.filter(
    (item) => item.id !== "agreed" && !item.pending && !seen.has(item.id),
  );
  if (!arrived.length) return;
  arrivalPage = arrived.length === 1 ? arrived[0].id : null;
  $("page-arrival-text").textContent = arrivalPage
    ? `${arrived[0].title} is ready`
    : `${plural(arrived.length, "page")} are ready`;
  $("page-arrival-view").textContent = arrivalPage ? "View" : "Pages";
  $("page-arrival").hidden = false;
  arrivalTimer = setTimeout(hideArrival, 5500);
}
$("page-arrival-view").addEventListener("click", () => {
  hideArrival();
  if (arrivalPage) show(arrivalPage);
  else openDrawer();
});
$("page-arrival-dismiss").addEventListener("click", hideArrival);
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
  const place = placeIn(plan.revision, [
    ...pages.map((item) => item.id),
    ...(editable ? ["feedback"] : []),
  ]);
  const opened = location.hash.slice(1) || query.get("target");
  show(location.hash.slice(1) || place?.page || "", query.get("target"), {
    keepScroll: false,
    push: false,
  });
  if (place?.top && !opened) restoreScroll(place.top);
  window.addEventListener("popstate", () => {
    const url = new URL(location.href);
    show(url.hash.slice(1) || pages[0].id, url.searchParams.get("target"), {
      push: false,
    });
  });
  if (mode === "preview" && query.get("quote")) {
    const range = findText($("page-content"), query.get("quote"));
    if (range) {
      highlight("plan-preview", [range]);
      range.startContainer.parentElement?.scrollIntoView({ block: "center" });
    }
  }
  if (online && mode !== "preview") {
    // A reload returns to the past revision that was on screen.
    poll().then(() => {
      if (editable && placeStore.tab === "past" && selectedTab === "current")
        if (placeStore.past) void openPast(placeStore.past);
    });
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
