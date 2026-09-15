const $ = (id) => document.getElementById(id);
const plan = JSON.parse($("plan-data").textContent);
const session = JSON.parse($("session-config").textContent);
const reviewAlerts = createReviewAlerts({
  window,
  button: $("notifications"),
  sessionId: session.sessionId,
  plan,
  open: (href) => {
    const url = new URL(href, location.href);
    if (url.pathname === location.pathname) show(url.hash.slice(1));
    else location.assign(url.href);
  },
});
const agreements = plan.agreements || [];
const builtInAgreed = !plan.pages.some((item) => item.id === "agreed");
const pages = [
  ...plan.pages,
  ...(builtInAgreed ? [{ id: "agreed", title: "Agreed", html: "" }] : []),
];
let agreementId =
  agreements.find((entry) => entry.state !== "retired")?.id ||
  agreements[0]?.id;
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
const storageKey = `interactive-plan:${session.sessionId || "offline"}:${plan.artifactId}:${plan.revision}`;
let state = {
  notes: [],
  choices: {},
  submitted: null,
  pending: null,
};
try {
  const saved = JSON.parse(localStorage.getItem(storageKey));
  if (saved && Array.isArray(saved.notes) && saved.choices) state = saved;
} catch {
  /* The in-memory draft and export remain usable. */
}
delete state.theme;
let page = plan.pages[0],
  remote = null,
  connected = false,
  editing = null,
  noteContext = null,
  selected = "",
  question = null,
  questionEvent = null,
  acceptance = null,
  submissionError = "",
  toastTimer;
const charts = new Map();
const snapshot = () =>
  JSON.stringify({ notes: state.notes, choices: state.choices });
const dirty = () => state.notes.length + Object.keys(state.choices).length;
const current = () =>
  remote?.current?.artifactId === plan.artifactId &&
  remote?.current?.revision === plan.revision;
function notify(message) {
  $("toast").textContent = message;
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => ($("toast").hidden = true), 4000);
}
function persist() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(state));
    $("storage-status").textContent = "Draft saved locally.";
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
  $("theme").textContent = activeTheme === "dark" ? "Light mode" : "Dark mode";
  for (const chart of charts.values())
    chart.setOption(chartTheme(chart.getOption()));
  renderDiagrams($("page-content"));
}
function show(id, targetId = null) {
  const feedback = id === "feedback";
  $("reading").hidden = feedback;
  $("feedback").hidden = !feedback;
  if (!feedback) {
    page = pages.find((item) => item.id === id) || pages[0];
    for (const chart of charts.values()) chart.dispose();
    charts.clear();
    $("page-title").textContent = page.title;
    $("page-content").innerHTML = page.html;
    if (page.id === "agreed" && builtInAgreed) renderAgreements();
    restoreChoices();
    if (!(page.id === "agreed" && builtInAgreed)) enhance($("page-content"));
    window.dispatchEvent(
      new CustomEvent("plan:page", {
        detail: { page, element: $("page-content") },
      }),
    );
  }
  for (const button of $("navigation").children) {
    if (button.dataset.page === (feedback ? "feedback" : page.id))
      button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  }
  const url = new URL(location.href);
  url.hash = feedback ? "feedback" : page.id;
  url.searchParams.delete("target");
  if (targetId) url.searchParams.set("target", targetId);
  history.replaceState(null, "", url);
  (feedback ? $("feedback").querySelector("h1") : $("page-title")).focus({
    preventScroll: true,
  });
  window.scrollTo(0, 0);
  const target = targetId && $(targetId);
  if (!feedback && target && $("page-content").contains(target)) {
    for (let ancestor = target; ancestor; ancestor = ancestor.parentElement)
      if (ancestor.tagName === "DETAILS") ancestor.open = true;
    if (!target.hasAttribute("tabindex")) target.tabIndex = -1;
    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: "center" });
  }
  $("quote").hidden = true;
  review();
}
function openNote(topic, anchor, quote = "", id = null, entryId = null) {
  noteContext = {
    topic,
    anchor,
    quote,
    ...(entryId ? { agreementId: entryId } : {}),
  };
  editing = id;
  $("note-anchor").textContent = anchor;
  $("note-quote").textContent = quote;
  $("note-quote").hidden = !quote;
  $("note-text").value = id
    ? state.notes.find((note) => note.id === id).text
    : "";
  $("note-title").textContent = id ? "Edit note" : "Add note";
  $("note-form").querySelector('[type="submit"]').textContent = id
    ? "Save changes"
    : "Add to feedback";
  $("note-dialog").showModal();
  $("note-text").focus();
  $("quote").hidden = true;
}
function renderAgreements() {
  const root = $("page-content");
  if (!agreements.length) {
    root.innerHTML = '<p class="muted">No agreements recorded yet.</p>';
    return;
  }
  root.innerHTML =
    '<div class="agreement-layout"><nav class="agreement-index" aria-label="Agreements"></nav><article class="agreement-detail"></article></div>';
  const index = root.querySelector(".agreement-index");
  const detail = root.querySelector(".agreement-detail");
  const retired = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "No longer applies";
  retired.append(summary);
  const select = (entry) => {
    agreementId = entry.id;
    for (const chart of charts.values()) chart.dispose();
    charts.clear();
    for (const button of index.querySelectorAll("button")) {
      if (button.dataset.agreement === entry.id)
        button.setAttribute("aria-current", "true");
      else button.removeAttribute("aria-current");
    }
    detail.replaceChildren();
    const head = document.createElement("div");
    head.className = "group-head";
    const title = document.createElement("h2");
    title.textContent = entry.title;
    const note = document.createElement("button");
    note.className = "btn quiet";
    note.textContent = "Add note";
    note.onclick = () => openNote("agreed", entry.title, "", null, entry.id);
    head.append(title, note);
    detail.append(head);
    const label =
      entry.state === "reopened"
        ? "Revisiting"
        : entry.state === "retired"
          ? "No longer applies"
          : entry.change === "new"
            ? "New"
            : entry.change === "updated"
              ? "Updated"
              : "";
    if (label) {
      const marker = document.createElement("p");
      marker.className = "agreement-label";
      marker.textContent = label;
      detail.append(marker);
    }
    const content = document.createElement("div");
    content.innerHTML = entry.html;
    detail.append(content);
    const source = document.createElement("details");
    const heading = document.createElement("summary");
    heading.textContent = "Source";
    const text = document.createElement("p");
    text.textContent = entry.source;
    source.append(heading, text);
    detail.append(source);
    if (entry.href) {
      const row = document.createElement("p");
      row.className = "agreement-source small";
      const link = document.createElement("a");
      link.href = entry.href;
      link.target = "_blank";
      link.rel = "noopener";
      link.textContent = "Open source ↗";
      row.append(link);
      const url = new URL(entry.href, location.href);
      const label = document.createElement("span");
      label.textContent = `${url.pathname.split("/").pop()}${url.hash}`;
      row.append(label);
      detail.append(row);
    }
    enhance(content);
  };
  for (const entry of agreements) {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.agreement = entry.id;
    button.textContent = entry.title;
    button.onclick = () => select(entry);
    (entry.state === "retired" ? retired : index).append(button);
  }
  if (retired.children.length > 1) index.append(retired);
  const entry =
    agreements.find((item) => item.id === agreementId) || agreements[0];
  retired.open = entry.state === "retired";
  select(entry);
}
function noteCard(note) {
  const box = document.createElement("div");
  box.className = "note";
  const title = document.createElement("h3");
  title.textContent = note.anchor;
  box.append(title);
  if (note.quote) {
    const quote = document.createElement("blockquote");
    quote.textContent = note.quote;
    box.append(quote);
  }
  const text = document.createElement("p");
  text.textContent = note.text;
  box.append(text);
  const actions = document.createElement("div");
  actions.className = "row";
  for (const action of ["Edit", "Remove"]) {
    const button = document.createElement("button");
    button.className = "btn quiet";
    button.textContent = action;
    button.onclick = () => {
      if (action === "Edit")
        openNote(
          note.topic,
          note.anchor,
          note.quote,
          note.id,
          note.agreementId,
        );
      else {
        state.notes = state.notes.filter((item) => item.id !== note.id);
        save();
      }
    };
    actions.append(button);
  }
  box.append(actions);
  return box;
}
function review() {
  const unchanged = state.submitted?.snapshot === snapshot();
  const unsent = unchanged ? 0 : dirty();
  document.querySelectorAll(".count").forEach((element) => {
    element.textContent = unsent;
    element.hidden = !unsent;
  });
  $("review").classList.toggle("primary", unsent > 0);
  $("review").classList.toggle("quiet", !unsent);
  $("feedback-groups").replaceChildren();
  for (const topic of pages) {
    const notes = state.notes.filter((note) => note.topic === topic.id),
      choices = Object.entries(state.choices).filter(
        ([, choice]) => choice.topic === topic.id,
      );
    if (!notes.length && !choices.length) continue;
    const group = document.createElement("section");
    group.className = "feedback-group";
    const head = document.createElement("div");
    head.className = "group-head";
    const heading = document.createElement("h2");
    heading.textContent = topic.title;
    head.append(heading);
    group.append(head);
    for (const [id, choice] of choices) {
      const row = document.createElement("p");
      row.textContent = `${choice.label}: ${choice.value}`;
      const clear = document.createElement("button");
      clear.className = "btn quiet";
      clear.textContent = "Clear choice";
      clear.onclick = () => {
        delete state.choices[id];
        restoreChoices();
        save();
      };
      row.append(clear);
      group.append(row);
    }
    notes.forEach((note) => group.append(noteCard(note)));
    $("feedback-groups").append(group);
  }
  $("overall-notes").replaceChildren(
    ...state.notes.filter((note) => note.topic === "overall").map(noteCard),
  );
  $("submit").disabled = !dirty() || unchanged || !connected || !current();
  $("submit").textContent = unchanged ? "Submitted" : "Submit feedback";
  $("submit-status").textContent =
    submissionError ||
    (unchanged
      ? "Feedback saved."
      : dirty()
        ? "Review your feedback before submitting."
        : "No feedback added.");
  status();
}
function feedbackText() {
  const lines = [
    `Feedback: ${plan.title}`,
    `Artifact ${plan.artifactId}, revision ${plan.revision}`,
    "Feedback only. No implementation approval.",
  ];
  for (const choice of Object.values(state.choices))
    lines.push("", `${choice.label}: ${choice.value}`);
  for (const note of state.notes)
    lines.push(
      "",
      note.anchor,
      ...(note.quote ? ["Selected passage: " + note.quote] : []),
      note.text,
    );
  return lines.join("\n");
}
function groups() {
  return { choices: state.choices, notes: state.notes };
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
  if (!connected)
    throw Error("Reconnect to the local helper or export your feedback.");
  const response = await fetch("/api/feedback", {
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
function status() {
  void reviewAlerts.update(connected ? remote : null);
  const newer = remote?.current && !current();
  const canAccept =
    plan.kind === "plan" &&
    connected &&
    current() &&
    !dirty() &&
    ["ready", "updated"].includes(remote.stage);
  $("accept").disabled = !canAccept;
  $("accept").title = dirty()
    ? "Submit feedback and review the revised plan before accepting."
    : "";
  if (!remote) return;
  const stage = newer ? "updated" : remote.stage;
  $("agent-status").hidden =
    !newer &&
    !state.submitted &&
    !state.lastEvent &&
    !["submitted", "working", "needs_reply", "complete"].includes(stage);
  const titles = {
    ready: "Ready for feedback",
    submitted: "Waiting for the agent",
    working: "The agent is working on your feedback",
    needs_reply: "The agent has a question",
    updated: "An updated artifact is ready",
    complete:
      remote.accepted?.mode === "implement"
        ? "Plan accepted. Implementation requested."
        : "Plan accepted and saved.",
  };
  $("status-title").textContent = titles[stage] || stage;
  $("status-detail").textContent =
    stage === "needs_reply"
      ? remote.question?.text
      : stage === "submitted"
        ? "Your submission is saved."
        : stage === "working" && remote.acknowledgedAt
          ? "Acknowledged at " +
            new Date(remote.acknowledgedAt).toLocaleTimeString([], {
              hour: "2-digit",
              minute: "2-digit",
            })
          : stage === "updated"
            ? `${remote.current.title}, revision ${remote.current.revision}`
            : "";
  $("spinner").hidden = !["submitted", "working"].includes(stage);
  $("reply").hidden = stage !== "needs_reply" || newer;
  $("update").hidden = !newer;
  if (newer) $("update").href = remote.current.url;
  $("final-plan").hidden = stage !== "complete";
  $("plan-path").hidden = stage !== "complete";
  if (stage === "complete") {
    $("final-plan").href = remote.accepted.url;
    $("plan-path").textContent = remote.accepted.path;
  }
  if (
    state.submitted &&
    remote.acknowledged.includes(state.submitted.id) &&
    state.submitted.snapshot === snapshot()
  )
    $("submit-status").textContent = "Feedback received by the agent.";
  if (newer) {
    $("submit").disabled = true;
    $("submit-status").textContent =
      "Open the update to continue. This draft remains saved.";
  }
}
async function poll() {
  if (!session.sessionId || !/^https?:$/.test(location.protocol)) {
    connected = false;
    $("connection-status").textContent =
      "Local viewing. Feedback can be exported; live submission requires the session URL.";
    review();
    return;
  }
  try {
    const response = await fetch("/api/status");
    if (!response.ok) throw Error();
    const result = await response.json();
    if (result.sessionId !== session.sessionId) throw Error("Wrong session");
    remote = result;
    connected = true;
    $("connection-status").textContent = "";
    review();
  } catch {
    connected = false;
    $("connection-status").textContent =
      "Local helper disconnected. Your draft remains here; reconnect or export a copy.";
    $("submit").disabled = true;
    $("accept").disabled = true;
    $("agent-status").hidden = false;
    $("spinner").hidden = true;
    $("status-title").textContent = "Connection unavailable";
    $("status-detail").textContent =
      "Resume this planning session in the agent conversation.";
  }
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
  save();
  $("note-dialog").close();
  notify("Added to feedback.");
};
$("submit").onclick = async () => {
  submissionError = "";
  const currentSnapshot = snapshot();
  if (state.pending?.snapshot !== currentSnapshot)
    state.pending = {
      snapshot: currentSnapshot,
      event: envelope("feedback-only", feedbackText(), {
        groups: groups(),
      }),
    };
  persist();
  $("submit").disabled = true;
  try {
    const result = await send(state.pending.event);
    state.submitted = { snapshot: currentSnapshot, id: result.id };
    state.pending = null;
    save();
    $("agent-status").scrollIntoView({ block: "nearest" });
  } catch (error) {
    submissionError = error.message;
    $("submit").disabled = false;
    $("submit-status").textContent = error.message;
  }
};
$("export").onclick = () => {
  const event =
    state.pending?.event ||
    envelope("feedback-only", feedbackText(), { groups: groups() });
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
$("reply").onclick = () => {
  question = remote.question;
  questionEvent = null;
  $("question-text").textContent = question.text;
  $("question-reply").value = "";
  $("question-error").textContent = "";
  $("question-dialog").showModal();
  $("question-reply").focus();
};
$("question-form").onsubmit = async (event) => {
  event.preventDefault();
  const text = $("question-reply").value.trim();
  if (!text) return;
  if (questionEvent?.text !== text)
    questionEvent = envelope("clarification-reply", text, {
      questionId: question.id,
    });
  $("send-reply").disabled = true;
  try {
    const result = await send(questionEvent);
    state.lastEvent = result.id;
    save();
    $("question-dialog").close();
  } catch (error) {
    $("question-error").textContent = error.message;
  } finally {
    $("send-reply").disabled = false;
  }
};
$("accept").onclick = () => {
  $("accept-detail").textContent = `${plan.title}, revision ${plan.revision}`;
  $("accept-error").textContent = "";
  $("accept-dialog").showModal();
};
document.querySelectorAll("[data-accept-mode]").forEach(
  (button) =>
    (button.onclick = async () => {
      const mode = button.dataset.acceptMode;
      if (acceptance?.mode !== mode)
        acceptance = envelope(
          "accept-plan",
          `Accept ${plan.artifactId} revision ${plan.revision}. ${mode === "implement" ? "Start implementation of this plan." : "Save for later. Do not start implementation."}`,
          { mode },
        );
      document
        .querySelectorAll("[data-accept-mode]")
        .forEach((item) => (item.disabled = true));
      try {
        const result = await send(acceptance);
        state.lastEvent = result.id;
        save();
        $("accept-dialog").close();
        show("feedback");
        $("agent-status").scrollIntoView({ block: "nearest" });
      } catch (error) {
        $("accept-error").textContent = error.message;
      } finally {
        document
          .querySelectorAll("[data-accept-mode]")
          .forEach((item) => (item.disabled = false));
      }
    }),
);
document.addEventListener("click", (event) => {
  const close = event.target.closest("[data-close]");
  if (close) $(close.dataset.close).close();
  const navigation = event.target.closest("[data-page]");
  if (navigation) show(navigation.dataset.page);
  const comment = event.target.closest("[data-comment]");
  if (comment)
    openNote(
      page.id,
      comment.dataset.comment || page.title,
      "",
      null,
      page.id === "agreed" && builtInAgreed ? agreementId : null,
    );
  const choice = event.target.closest("[data-choice] [data-value]");
  if (choice) {
    const group = choice.closest("[data-choice]"),
      id = page.id + "/" + group.dataset.choice;
    if (state.choices[id]?.value === choice.dataset.value)
      delete state.choices[id];
    else
      state.choices[id] = {
        topic: page.id,
        label: group.dataset.label || group.dataset.choice,
        value: choice.dataset.value,
      };
    restoreChoices();
    save();
  }
});
document.addEventListener("selectionchange", () => {
  const selection = getSelection(),
    parent = selection?.anchorNode?.parentElement;
  selected = selection?.toString().trim() || "";
  $("quote").hidden = !(
    selected.length > 3 &&
    parent?.closest("#page-content") &&
    !document.querySelector("dialog[open]")
  );
});
$("quote").onpointerdown = (event) => event.preventDefault();
$("quote").onclick = () =>
  openNote(
    page.id,
    page.title,
    selected,
    null,
    page.id === "agreed" && builtInAgreed ? agreementId : null,
  );
$("page-comment").onclick = () => openNote(page.id, page.title);
$("overall-note").onclick = () => openNote("overall", "Overall feedback");
$("review").onclick = $("page-review").onclick = () => show("feedback");
$("theme").onclick = () => {
  preferredTheme = activeTheme = activeTheme === "dark" ? "light" : "dark";
  try {
    if (/^https?:$/.test(location.protocol))
      document.cookie = `interactive-plan-theme=${preferredTheme}; Path=/; SameSite=Strict; Max-Age=31536000`;
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

const libraries = {
  shiki: "https://esm.sh/shiki@3.12.2",
  mermaid:
    "https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.esm.min.mjs",
  katex: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js",
  katexCss: "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css",
  echarts: "https://cdn.jsdelivr.net/npm/echarts@6.0.0/dist/echarts.min.js",
};
const scripts = new Map();
let shikiTask,
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
async function renderCode(element) {
  const source = element.textContent;
  try {
    shikiTask ||= import(libraries.shiki);
    const { codeToHtml } = await shikiTask;
    const html = await codeToHtml(source, {
      lang: element.dataset.language,
      themes: { light: "github-light", dark: "github-dark" },
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
              primaryColor: color("--panel"),
              primaryTextColor: color("--ink"),
              primaryBorderColor: color("--muted"),
              lineColor: color("--muted"),
              fontFamily: "sans-serif",
            },
          });
          const result = await mermaid.render(
            "diagram-" + crypto.randomUUID(),
            element.dataset.source,
          );
          if (element.isConnected) element.innerHTML = result.svg;
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
    color: [color("--blue"), color("--muted")],
    textStyle: { color: color("--ink") },
    ...options,
  });
  instance.setOption(chartTheme(options));
  return instance;
}
function enhance(root) {
  root.querySelectorAll("[data-language]").forEach(renderCode);
  root.querySelectorAll("[data-math]").forEach(renderMath);
  renderDiagrams(root);
  root.querySelectorAll("[data-chart]").forEach((element) => {
    try {
      const options = JSON.parse(element.textContent);
      element.textContent = "";
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
  comment: (anchor, quote = "") =>
    openNote(
      page.id,
      anchor,
      quote,
      null,
      page.id === "agreed" && builtInAgreed ? agreementId : null,
    ),
  enhance,
};
document.title = plan.title;
$("artifact-title").textContent =
  `${plan.title} / ${plan.kind === "plan" ? "Final plan" : "Exploration"}`;
$("revision").textContent = `Revision ${plan.revision}`;
$("accept").hidden = plan.kind !== "plan";
for (const item of [
  ...pages.filter((item) => item.id !== "agreed"),
  pages.find((item) => item.id === "agreed"),
  { id: "feedback", title: "Feedback" },
]) {
  if (item.id === "agreed") {
    const divider = document.createElement("div");
    divider.className = "review-divider";
    divider.setAttribute("role", "separator");
    $("navigation").append(divider);
  }
  const button = document.createElement("button");
  button.dataset.page = item.id;
  button.textContent = item.title;
  $("navigation").append(button);
}
theme();
show(location.hash.slice(1), new URL(location.href).searchParams.get("target"));
poll();
setInterval(poll, 1500);
