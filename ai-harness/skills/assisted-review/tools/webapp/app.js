// Vanilla JS — no framework, no build step. Talks to the local Python
// daemon via fetch. Path-based routing (HTML5 history API):
//
//   /                                     → inbox
//   /r/<slug>/<key>                       → per-review (overview + threads)
//   /r/<slug>/<key>/<file/path>           → file view inside a review
//
// State below is the union of route + lazily-fetched data + transient UI.

const state = {
  // route
  route: { view: "inbox" },          // {view: 'inbox'|'review'|'file', slug, key, file}
  // fetched data
  inbox: null,                        // { reviews: [...] }
  review: null,                       // parsed review YAML (per current slug/key)
  source: null,                       // { file, content }
  sourceCache: new Map(),             // file path -> source content for editor previews
  fullTree: null,                     // { files: [...] } — fetched lazily on "show all" toggle
  diffSummary: null,                  // live git diff summary for current review/base
  diffFileCache: new Map(),           // `${base}\0${file}` -> per-file diff payload
  filePaneCache: new Map(),           // rendered file pane DOM by review/base/filter/file
  currentFilePaneKey: null,
  diffError: null,
  refOptions: null,                   // { refs: [...] } for base selector suggestions
  // ui
  inboxFilter: "needs_triage",        // 'needs_triage' | 'iterating' | 'done' | 'stale'
  showStale: false,
  diffVisible: defaultDiffVisible(),
  navTarget: localStorage.getItem("assistedReviewNavTarget") || "comments", // comments | hunks
  threadFilter: localStorage.getItem("assistedReviewThreadFilter") || "all", // all | comment | note
  cursorHunk: null,                   // { file, index } for hunk navigation
  baseDraft: "",
  expandedComments: new Set(),
  cursorCommentId: null,              // last navigated/clicked comment — Tab/S-Tab anchor
  treeFilter: {
    query: "",
    scope: "comments",                // comments | changed | all
    showIgnored: false,
    extensions: [],
    extensionQuery: "",
    extensionMenuOpen: false,
  },
  collapsedFolders: new Set(),        // folder paths the user has collapsed in the file tree
  newCommentTarget: null,             // { file, line, isRange, endLine } or null
  newThreadType: "comment",           // comment | note
  newCommentSuggestionExpanded: false,
  newCommentSuggestionDraft: "",
  editingBody: null,                  // commentId currently being edited inline
  editingSuggestion: null,            // commentId currently editing suggestion inline
  suggestionDrafts: new Map(),         // commentId -> original source replacement text
  refreshStatus: null,                 // refresh readiness for current review
  refreshPollId: null,
  preserveNavCursorForLoad: false,
  suppressGlobalEscapeUntil: 0,
  error: null,
};

const HIGHLIGHT_CACHE_LIMIT = 20000;
const highlightLineCache = new Map();
let focusedHunkElements = new Set();

const STATUS_OPTIONS = [
  { value: "open", label: "Open", icon: "circle-dot" },
  { value: "acknowledged", label: "Acknowledged", icon: "eye" },
  { value: "resolved", label: "Resolved", icon: "check-circle-2" },
  { value: "wontfix", label: "Won't fix", icon: "ban" },
];
const SKIP_SEND_STATUSES = new Set(["resolved", "wontfix"]);
const SENDABLE_ANCHOR_STATUSES = new Set(["current", "moved"]);
if (!["comments", "hunks"].includes(state.navTarget)) state.navTarget = "comments";
if (!["all", "comment", "note"].includes(state.threadFilter)) state.threadFilter = "all";

// === Helpers =======================================================

function defaultDiffVisible() {
  const stored = localStorage.getItem("assistedReviewDiffVisible");
  if (stored !== null) return stored === "1";
  return localStorage.getItem("assistedReviewViewMode") !== "source";
}

function shortSha(sha) {
  return (sha || "").slice(0, 7);
}

function commentLineRange(c) {
  if (c.start_line && c.line && c.start_line !== c.line) {
    return [c.start_line, c.line];
  }
  return [c.line, c.line];
}

function reviewThreads() {
  const review = state.review?.review;
  if (!review) return [];
  if (!Array.isArray(review.threads)) review.threads = [];
  return review.threads;
}

function overviewId(kind) {
  return `overview:${kind}`;
}

function overviewKind(id) {
  const match = /^overview:(summary|note)$/.exec(String(id || ""));
  return match ? match[1] : null;
}

function ensureOverviewBlock(kind) {
  const review = state.review?.review;
  if (!review) return { author: "ai", body: "", replies: [] };

  const current = review[kind];
  if (typeof current === "string") {
    review[kind] = { author: "ai", body: current, replies: [] };
  } else if (!current || typeof current !== "object" || Array.isArray(current)) {
    review[kind] = { author: "ai", body: "", replies: [] };
  } else {
    if (!["ai", "user"].includes(review[kind].author)) review[kind].author = "ai";
    if (typeof review[kind].body !== "string") review[kind].body = "";
    if (!Array.isArray(review[kind].replies)) review[kind].replies = [];
  }

  return review[kind];
}

function threadType(c) {
  return c?.type === "note" ? "note" : "comment";
}

function isNoteThread(c) {
  return threadType(c) === "note";
}

function visibleReviewThreads() {
  const filter = state.threadFilter;
  return reviewThreads().filter((c) => filter === "all" || threadType(c) === filter);
}

function threadCounts(threads = reviewThreads()) {
  let comments = 0;
  let notes = 0;
  threads.forEach((c) => {
    if (isNoteThread(c)) notes += 1;
    else comments += 1;
  });
  return { comments, notes, total: comments + notes };
}

function sendableCommentThreads() {
  return reviewThreads().filter((c) => threadType(c) === "comment" && !SKIP_SEND_STATUSES.has(c.status || "open"));
}

function findThread(id) {
  return reviewThreads().find((x) => x.id === id);
}

function findDiscussionTarget(id) {
  const kind = overviewKind(id);
  if (kind) return ensureOverviewBlock(kind);
  return findThread(id);
}

function resetNavigationCursors() {
  state.cursorCommentId = null;
  state.cursorHunk = null;
}

function hasSuggestion(c) {
  return Object.prototype.hasOwnProperty.call(c || {}, "suggestion");
}

function suggestionText(c) {
  return hasSuggestion(c) ? String(c.suggestion ?? "") : "";
}

function commentSendBlockReason(c) {
  if (!state.review?.target?.pr_number) return "Set target.pr_number to enable sending.";
  if (!c) return "Comment not found.";
  if (isNoteThread(c)) return "Notes stay local and cannot be sent to GitHub.";
  const status = c.status || "open";
  if (SKIP_SEND_STATUSES.has(status)) {
    return `Status is ${humanStatus(status)}. Set it to Open or Acknowledged before sending.`;
  }
  const anchorStatus = c.anchor_status || "current";
  if (!SENDABLE_ANCHOR_STATUSES.has(anchorStatus)) {
    return "Refresh or move the anchor before sending.";
  }
  return "";
}

function reviewSendBlockReason() {
  if (!state.review?.target?.pr_number) return "Set target.pr_number to enable submitting.";
  const activeThreads = sendableCommentThreads();
  if (activeThreads.length === 0) return "No open or acknowledged comments to submit.";
  const staleThread = activeThreads.find((c) => {
    const anchorStatus = c.anchor_status || "current";
    return !SENDABLE_ANCHOR_STATUSES.has(anchorStatus);
  });
  if (staleThread) return `Refresh or move ${staleThread.id} before submitting.`;
  return "";
}

function submissionSummary() {
  const sendableComments = sendableCommentThreads().length;
  const notes = threadCounts().notes;
  return { sendableComments, notes };
}

function severityOrder(sev) {
  return { critical: 0, high: 1, medium: 2, low: 3, info: 4 }[sev] ?? 5;
}

function confidenceOrder(confidence) {
  return { high: 0, medium: 1, low: 2 }[confidence] ?? 3;
}

function fileExtension(path) {
  const filename = String(path || "").split("/").pop() || "";
  if (!filename || filename.startsWith(".") && filename.indexOf(".", 1) === -1) return "";
  const idx = filename.lastIndexOf(".");
  return idx > 0 && idx < filename.length - 1 ? filename.slice(idx + 1).toLowerCase() : "";
}

function uniqueSortedExtensions(paths) {
  return Array.from(new Set(paths.map(fileExtension).filter(Boolean))).sort((a, b) => a.localeCompare(b));
}

function normalizeExtensionInput(value) {
  return String(value || "").trim().replace(/^\./, "").toLowerCase();
}

function formatExtensionSummary(extensions) {
  if (!extensions.length) return "Types: All";
  const visible = extensions.slice(0, 2).map((ext) => `.${ext}`).join(", ");
  const overflow = extensions.length > 2 ? ` +${extensions.length - 2}` : "";
  return `Types: ${visible}${overflow}`;
}

function unionPaths(...pathLists) {
  return Array.from(new Set(pathLists.flat().filter(Boolean))).sort((a, b) => a.localeCompare(b));
}

function diffFiles() {
  return state.diffSummary?.files || [];
}

function diffFileMap() {
  return Object.fromEntries(diffFiles().map((f) => [f.file, f]));
}

function diffStatForFile(filePath) {
  return diffFileMap()[filePath] || null;
}

function diffCacheKey(filePath, baseRef = null) {
  return `${baseRef || state.diffSummary?.base_ref || ""}\0${filePath}`;
}

function formatDiffStat(file) {
  if (!file) return "";
  if (file.binary) return `<span class="diffstat binary">bin</span>`;
  const additions = Number(file.additions || 0);
  const deletions = Number(file.deletions || 0);
  return `
    <span class="diffstat" title="${additions} additions, ${deletions} deletions">
      <span class="diff-add">+${additions}</span><span class="diff-del">-${deletions}</span>
    </span>
  `;
}

function humanStatus(status) {
  return STATUS_OPTIONS.find((option) => option.value === status)?.label || status || "Open";
}

function humanSeverity(severity) {
  return {
    critical: "Critical",
    high: "Major",
    medium: "Medium",
    low: "Minor",
    info: "Info",
  }[severity] || severity || "Info";
}

function humanConfidence(confidence) {
  return {
    high: "High",
    medium: "Medium",
    low: "Low",
  }[confidence] || confidence || "Medium";
}

function chipIcon(kind, value) {
  const maps = {
    severity: {
      critical: "octagon-alert",
      high: "triangle-alert",
      medium: "circle-alert",
      low: "info",
      info: "info",
    },
    confidence: {
      high: "badge-check",
      medium: "badge-help",
      low: "badge-alert",
    },
    status: {
      ...Object.fromEntries(STATUS_OPTIONS.map((option) => [option.value, option.icon])),
    },
    type: {
      comment: "message-square",
      note: "bookmark",
    },
    category: {},
  };
  return maps[kind]?.[value] || (kind === "category" ? "tag" : "circle");
}

function escapeHtml(text) {
  return String(text ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderMarkdown(text) {
  // Defer to marked when the CDN script loaded; fall back to a
  // plain-escape on CDN miss so comment bodies always render *something*
  // safe instead of throwing. The sanitizer below removes dangerous raw
  // HTML while preserving normal Markdown structure.
  const src = String(text ?? "");
  if (window.marked) {
    return enhanceRenderedMarkdown(sanitizeRenderedMarkdown(window.marked.parse(src, { breaks: false, gfm: true })));
  }
  return `<pre class="comment-body-fallback">${escapeHtml(src)}</pre>`;
}

function sanitizeRenderedMarkdown(html) {
  const template = document.createElement("template");
  template.innerHTML = html;
  const dropWithContents = new Set(["script", "style", "iframe", "object", "embed", "link", "meta", "base"]);
  const allowedTags = new Set([
    "a", "blockquote", "br", "code", "del", "details", "em", "h1", "h2", "h3",
    "h4", "h5", "h6", "hr", "input", "kbd", "li", "ol", "p", "pre", "s",
    "strong", "sub", "summary", "sup", "table", "tbody", "td", "th", "thead",
    "tr", "ul",
  ]);
  const allowedAttrs = {
    a: new Set(["href", "title"]),
    code: new Set(["class"]),
    input: new Set(["checked", "disabled", "type"]),
    details: new Set(["open"]),
    th: new Set(["align"]),
    td: new Set(["align"]),
  };

  template.content.querySelectorAll(Array.from(dropWithContents).join(",")).forEach((el) => {
    el.remove();
  });

  Array.from(template.content.querySelectorAll("*")).forEach((el) => {
    const tag = el.tagName.toLowerCase();
    if (!allowedTags.has(tag)) {
      el.replaceWith(...Array.from(el.childNodes));
      return;
    }

    Array.from(el.attributes).forEach((attr) => {
      const name = attr.name.toLowerCase();
      const rawValue = attr.value.trim();
      const value = rawValue.toLowerCase();
      const allowedForTag = allowedAttrs[tag] || new Set();
      if (name.startsWith("on") || !allowedForTag.has(name)) {
        el.removeAttribute(attr.name);
        return;
      }
      if (tag === "a" && name === "href" && !isSafeMarkdownHref(rawValue)) {
        el.removeAttribute(attr.name);
        return;
      }
      if (tag === "code" && name === "class" && !/^language-[a-z0-9_+-]+$/i.test(rawValue)) {
        el.removeAttribute(attr.name);
        return;
      }
      if (tag === "input") {
        if (name === "type" && value !== "checkbox") {
          el.removeAttribute(attr.name);
          return;
        }
        if (name === "checked" || name === "disabled") {
          el.setAttribute(name, "");
          return;
        }
      }
    });

    if (tag === "a") {
      el.setAttribute("target", "_blank");
      el.setAttribute("rel", "noopener noreferrer");
    }
    if (tag === "input") {
      el.setAttribute("disabled", "");
    }
  });
  return template.innerHTML;
}

function isSafeMarkdownHref(href) {
  const value = String(href || "").trim();
  if (!value) return false;
  if (value.startsWith("#") || value.startsWith("/") || value.startsWith("./") || value.startsWith("../")) return true;
  try {
    const url = new URL(value, window.location.href);
    return ["http:", "https:", "mailto:"].includes(url.protocol);
  } catch {
    return false;
  }
}

function enhanceRenderedMarkdown(html) {
  const template = document.createElement("template");
  template.innerHTML = html;
  template.content.querySelectorAll("pre code").forEach((code) => {
    if (!window.hljs) return;
    const languageClass = Array.from(code.classList).find((cls) => cls.startsWith("language-"));
    const language = languageClass ? languageClass.slice("language-".length) : "";
    try {
      const result = language && window.hljs.getLanguage(language)
        ? window.hljs.highlight(code.textContent || "", { language, ignoreIllegals: true })
        : window.hljs.highlightAuto(code.textContent || "");
      code.innerHTML = result.value;
      code.classList.add("hljs");
    } catch {
      code.textContent = code.textContent || "";
    }
  });
  return template.innerHTML;
}

function closeOpenDisclosureMenus(clickedTarget) {
  const activeMenu = clickedTarget?.closest?.("details.tree-type-filter, details.status-menu, details.comment-menu") || null;
  document.querySelectorAll("details.tree-type-filter[open], details.status-menu[open], details.comment-menu[open]").forEach((menu) => {
    if (menu === activeMenu) return;
    menu.open = false;
    if (menu.classList.contains("tree-type-filter")) {
      state.treeFilter.extensionMenuOpen = false;
    }
  });
}

function showToast(message, opts = {}) {
  const el = document.getElementById("toast");
  const kind = opts.kind || "info";
  const title = opts.title || String(message || "");
  const detail = opts.detail || "";
  el.className = `toast ${kind}`;
  el.innerHTML = `
    <div class="toast-title">${escapeHtml(title)}</div>
    ${detail ? `<div class="toast-detail">${escapeHtml(detail)}</div>` : ""}
  `;
  el.classList.add("show");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => el.classList.remove("show"), opts.duration || (kind === "error" ? 8000 : 3200));
}

function showError(err, title = "Action failed") {
  const detail = err?.detail || err?.message || String(err || "");
  showToast(title, { kind: "error", detail, duration: 9000 });
}

function apiError(payload, fallback) {
  const err = new Error(payload.error || fallback);
  if (payload.detail) err.detail = payload.detail;
  if (payload.warning) err.detail = payload.warning;
  return err;
}

function relativeAge(timestampSecs) {
  if (!timestampSecs) return "—";
  const now = Date.now() / 1000;
  const delta = now - timestampSecs;
  if (delta < 60) return `${Math.round(delta)}s`;
  if (delta < 3600) return `${Math.round(delta / 60)}m`;
  if (delta < 86400) return `${Math.round(delta / 3600)}h`;
  return `${Math.round(delta / 86400)}d`;
}

// === Language detection (from demo, unchanged) =====================

const EXTENSION_REMAPS = {
  zsh: "bash", sh: "bash", toml: "ini", yml: "yaml",
  jsx: "javascript", tsx: "typescript", htm: "xml", html: "xml",
};
const FILENAME_REMAPS = {
  "tmux.conf": "bash", "Dockerfile": "dockerfile",
  "Makefile": "makefile", "GNUmakefile": "makefile",
};
const SHEBANG_INTERPRETERS = {
  bash: "bash", sh: "bash", zsh: "bash", python: "python",
  python3: "python", node: "javascript", ruby: "ruby",
  perl: "perl", lua: "lua",
};

function detectLanguage(filePath, content) {
  const filename = filePath.split("/").pop();
  if (FILENAME_REMAPS[filename]) return FILENAME_REMAPS[filename];
  const ext = (filename.includes(".") ? filename.split(".").pop() : "").toLowerCase();
  if (ext) {
    if (EXTENSION_REMAPS[ext]) return EXTENSION_REMAPS[ext];
    if (window.hljs && window.hljs.getLanguage(ext)) return ext;
  }
  if (content) {
    const firstLine = content.split("\n", 1)[0] || "";
    if (firstLine.startsWith("#!")) {
      const match =
        firstLine.match(/(?:env\s+)?([a-zA-Z][a-zA-Z0-9_-]*)\s*$/m) ||
        firstLine.match(/\/([a-zA-Z][a-zA-Z0-9_-]*)(?:\s|$)/);
      if (match && SHEBANG_INTERPRETERS[match[1]]) return SHEBANG_INTERPRETERS[match[1]];
    }
  }
  return null;
}

function renderHighlightedLine(line, language) {
  const safeLine = line || " ";
  const cacheKey = `${window.hljs ? "hljs" : "plain"}\0${language || ""}\0${safeLine}`;
  if (highlightLineCache.has(cacheKey)) return highlightLineCache.get(cacheKey);
  if (highlightLineCache.size > HIGHLIGHT_CACHE_LIMIT) highlightLineCache.clear();
  if (!window.hljs) {
    const plainHtml = escapeHtml(line) || "&nbsp;";
    highlightLineCache.set(cacheKey, plainHtml);
    return plainHtml;
  }
  try {
    const result = language
      ? window.hljs.highlight(safeLine, { language, ignoreIllegals: true })
      : window.hljs.highlightAuto(safeLine);
    const highlightedHtml = result.value || "&nbsp;";
    highlightLineCache.set(cacheKey, highlightedHtml);
    return highlightedHtml;
  } catch {
    const fallbackHtml = escapeHtml(line) || "&nbsp;";
    highlightLineCache.set(cacheKey, fallbackHtml);
    return fallbackHtml;
  }
}

const CODEMIRROR_MODE_URL = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/%N/%N.min.js";

function codeMirrorModeInfo(filePath, language) {
  if (!window.CodeMirror) return null;
  const cm = window.CodeMirror;
  if (language && cm.findModeByName) {
    const byLanguage = cm.findModeByName(language);
    if (byLanguage && byLanguage.mode !== "null") return byLanguage;
  }
  const filename = filePath ? filePath.split("/").pop() : "";
  if (filename && cm.findModeByFileName) {
    const byFilename = cm.findModeByFileName(filename);
    if (byFilename && byFilename.mode !== "null") return byFilename;
  }
  const ext = filename && filename.includes(".") ? filename.split(".").pop() : "";
  if (ext && cm.findModeByExtension) {
    const byExtension = cm.findModeByExtension(ext);
    if (byExtension && byExtension.mode !== "null") return byExtension;
  }
  return null;
}

function markdownModeInfo() {
  if (!window.CodeMirror?.findModeByName) return { mode: "markdown", mime: "text/x-markdown" };
  return window.CodeMirror.findModeByName("markdown") || { mode: "markdown", mime: "text/x-markdown" };
}

function modeSpec(modeInfo) {
  return modeInfo?.mime || modeInfo?.mode || null;
}

function editorValue(el) {
  return el?._cm ? el._cm.getValue() : (el?.value || "");
}

function normalizeSuggestionText(text) {
  const value = String(text ?? "");
  return /\S/.test(value) ? value.replace(/\n+$/, "") : "";
}

function sourceLinesForFile(filePath, sourceLinesArg = null) {
  if (sourceLinesArg) return sourceLinesArg;
  if (state.source?.file === filePath) return state.source.content.split("\n");
  const cached = state.sourceCache.get(filePath);
  return cached ? cached.split("\n") : null;
}

async function ensureSourceForFile(filePath) {
  if (!filePath) return null;
  if (state.source?.file === filePath && !state.source.unavailable) return state.source.content;
  if (state.sourceCache.has(filePath)) return state.sourceCache.get(filePath);
  const content = await fetchSource(state.route.slug, state.route.key, filePath);
  state.sourceCache.set(filePath, content);
  return content;
}

async function ensureDiffForFile(filePath) {
  if (!filePath || !state.review) return null;
  const key = diffCacheKey(filePath);
  if (state.diffFileCache.has(key)) return state.diffFileCache.get(key);
  const payload = await fetchDiffFile(state.route.slug, state.route.key, filePath, {
    base: state.diffSummary?.base_ref || state.review?.target?.base_ref || "",
  });
  const fileDiff = (payload.files || []).find((f) => f.file === filePath) || {
    file: filePath,
    additions: 0,
    deletions: 0,
    hunks: [],
    hunk_count: 0,
  };
  fileDiff.base_ref = payload.base_ref;
  state.diffFileCache.set(key, fileDiff);
  return fileDiff;
}

function sourceTextForRange(filePath, startLine, endLine, sourceLinesArg = null) {
  const sourceLines = sourceLinesForFile(filePath, sourceLinesArg);
  if (!sourceLines || !startLine || !endLine) return "";
  return sourceLines.slice(startLine - 1, endLine).join("\n");
}

function originalTextForComment(c, sourceLinesArg = null) {
  const [s, e] = commentLineRange(c);
  return sourceTextForRange(c.file, s, e, sourceLinesArg);
}

function originalTextForNewComment() {
  const t = state.newCommentTarget;
  if (!t) return "";
  return sourceTextForRange(t.file, t.line, t.endLine || t.line);
}

function leadingWhitespace(line) {
  return (line.match(/^[\t ]*/) || [""])[0];
}

function nonBlankLines(text) {
  return String(text ?? "").split("\n").filter((line) => /\S/.test(line));
}

function indentationWidth(prefix) {
  return Array.from(prefix).reduce((width, ch) => width + (ch === "\t" ? 4 : 1), 0);
}

function minIndentWidth(lines) {
  const indents = lines
    .filter((line) => /\S/.test(line))
    .map((line) => indentationWidth(leadingWhitespace(line)));
  return indents.length ? Math.min(...indents) : 0;
}

function alignedIndentationChanged(originalLines, suggestedLines) {
  const originalTrimmed = originalLines.map((line) => line.trimStart());
  const suggestedTrimmed = suggestedLines.map((line) => line.trimStart());
  const rows = originalLines.length + 1;
  const cols = suggestedLines.length + 1;
  const lcs = Array.from({ length: rows }, () => Array(cols).fill(0));

  for (let i = originalLines.length - 1; i >= 0; i -= 1) {
    for (let j = suggestedLines.length - 1; j >= 0; j -= 1) {
      if (originalTrimmed[i] === suggestedTrimmed[j]) {
        lcs[i][j] = lcs[i + 1][j + 1] + 1;
      } else {
        lcs[i][j] = Math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }
  }

  let i = 0;
  let j = 0;
  while (i < originalLines.length && j < suggestedLines.length) {
    if (originalTrimmed[i] === suggestedTrimmed[j]) {
      if (leadingWhitespace(originalLines[i]) !== leadingWhitespace(suggestedLines[j])) {
        return true;
      }
      i += 1;
      j += 1;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      i += 1;
    } else {
      j += 1;
    }
  }
  return false;
}

function looksLikeBlockDeindent(originalLines, suggestedLines) {
  const originalIndent = minIndentWidth(originalLines);
  const suggestedIndent = minIndentWidth(suggestedLines);
  if (originalIndent === 0 || suggestedIndent >= originalIndent) return false;
  const deindentedSuggestedLines = suggestedLines.filter((line) => (
    /\S/.test(line) && indentationWidth(leadingWhitespace(line)) < originalIndent
  ));
  return deindentedSuggestedLines.length >= Math.max(1, Math.ceil(suggestedLines.length / 2));
}

function indentationWarning(originalText, suggestedText) {
  const suggested = normalizeSuggestionText(suggestedText);
  if (!/\S/.test(suggested)) return "";
  const originalLines = nonBlankLines(originalText);
  const suggestedLines = nonBlankLines(suggested);
  if (
    alignedIndentationChanged(originalLines, suggestedLines) ||
    looksLikeBlockDeindent(originalLines, suggestedLines)
  ) {
    return "Possible indentation change; GitHub applies whitespace exactly.";
  }
  return "";
}

function splitDiffLines(text) {
  const value = String(text ?? "").replace(/\n$/, "");
  return value === "" ? [] : value.split("\n");
}

function renderSuggestionDiffTable(originalText, suggestedText, language, startLine = null) {
  const originalLines = splitDiffLines(originalText);
  const suggestedLines = splitDiffLines(suggestedText);
  const removedRows = originalLines.map((line, i) => `
    <tr class="diff-line removed">
      <td class="diff-num">${startLine ? startLine + i : ""}</td>
      <td class="diff-marker">−</td>
      <td class="diff-code">${renderHighlightedLine(line, language)}</td>
    </tr>
  `).join("");
  const addedRows = suggestedLines.map((line) => `
    <tr class="diff-line added">
      <td class="diff-num"></td>
      <td class="diff-marker">+</td>
      <td class="diff-code">${renderHighlightedLine(line, language)}</td>
    </tr>
  `).join("");
  return `
    <div class="diff-table-scroll">
      <table class="diff-table"><tbody>
        ${removedRows}
        ${addedRows}
      </tbody></table>
    </div>
  `;
}

function updateSuggestionPreview(previewEl, warningEl, originalText, suggestedText, language, startLine = null) {
  if (previewEl) {
    previewEl.innerHTML = renderSuggestionDiffTable(originalText, suggestedText, language, startLine);
  }
  if (warningEl) {
    const warning = indentationWarning(originalText, suggestedText);
    warningEl.textContent = warning;
    warningEl.hidden = !warning;
  }
}

function bindCodeEditor(textarea, opts = {}) {
  if (!textarea || textarea._cm || !window.CodeMirror) return null;
  window.CodeMirror.modeURL = CODEMIRROR_MODE_URL;
  const editor = window.CodeMirror.fromTextArea(textarea, {
    mode: modeSpec(opts.modeInfo) || null,
    lineNumbers: false,
    lineWrapping: opts.lineWrapping ?? false,
    indentUnit: 4,
    tabSize: 4,
    indentWithTabs: opts.indentWithTabs ?? false,
    viewportMargin: Infinity,
    extraKeys: {
      "Cmd-Enter": () => opts.onSave?.(),
      "Ctrl-Enter": () => opts.onSave?.(),
      "Esc": () => {
        suppressGlobalEscapeCollapse();
        opts.onCancel?.();
      },
      "Tab": (cm) => cm.execCommand("indentMore"),
      "Shift-Tab": (cm) => cm.execCommand("indentLess"),
    },
  });
  textarea._cm = editor;
  if (opts.modeInfo?.mode && window.CodeMirror.autoLoadMode) {
    window.CodeMirror.autoLoadMode(editor, opts.modeInfo.mode);
  }
  editor.on("change", () => {
    editor.save();
    opts.onChange?.(editor.getValue());
  });
  requestAnimationFrame(() => editor.refresh());
  return editor;
}

// === Router ========================================================

function parseRoute(path) {
  if (path === "/" || path === "") return { view: "inbox" };
  const m = path.match(/^\/r\/([^/]+)\/([^/]+?)(?:\/(.+))?$/);
  if (!m) return { view: "inbox" };
  return {
    view: m[3] ? "file" : "review",
    slug: decodeURIComponent(m[1]),
    key: decodeURIComponent(m[2]),
    file: m[3] ? decodeURIComponent(m[3]) : undefined,
  };
}

function buildPath(route) {
  if (route.view === "inbox") return "/";
  const segs = ["r", encodeURIComponent(route.slug), encodeURIComponent(route.key)];
  if (route.file) {
    segs.push(route.file.split("/").map(encodeURIComponent).join("/"));
  }
  return "/" + segs.join("/");
}

function navigate(route, replace = false, opts = {}) {
  state.preserveNavCursorForLoad = Boolean(opts.preserveNavCursor);
  const path = buildPath(route);
  if (replace) {
    window.history.replaceState(route, "", path);
  } else {
    window.history.pushState(route, "", path);
  }
  return loadRoute(route);
}

window.addEventListener("popstate", (e) => {
  const route = e.state || parseRoute(window.location.pathname);
  loadRoute(route);
});

// === Data loaders ==================================================

async function fetchInbox() {
  const r = await fetch("/api/reviews");
  if (!r.ok) throw new Error(`inbox load failed: ${r.status}`);
  return r.json();
}

async function fetchReview(slug, key) {
  const r = await fetch(`/api/review/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`);
  if (!r.ok) throw new Error(`review load failed: ${r.status}`);
  return r.json();
}

async function fetchTree(slug, key, opts = {}) {
  const params = new URLSearchParams();
  if (opts.includeIgnored) params.set("include_ignored", "1");
  const qs = params.toString();
  const r = await fetch(`/api/tree/${encodeURIComponent(slug)}/${encodeURIComponent(key)}${qs ? `?${qs}` : ""}`);
  if (!r.ok) throw new Error(`tree load failed: ${r.status}`);
  return r.json();
}

async function fetchRefreshStatus(slug, key) {
  const r = await fetch(`/api/refresh-status/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`);
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `refresh status failed: ${r.status}`);
  return payload;
}

async function fetchDiffSummary(slug, key, opts = {}) {
  const params = new URLSearchParams();
  if (opts.base) params.set("base", opts.base);
  const qs = params.toString();
  const r = await fetch(`/api/diff/${encodeURIComponent(slug)}/${encodeURIComponent(key)}${qs ? `?${qs}` : ""}`);
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `diff load failed: ${r.status}`);
  return payload;
}

async function fetchDiffFile(slug, key, file, opts = {}) {
  const params = new URLSearchParams({ file });
  if (opts.base) params.set("base", opts.base);
  const r = await fetch(`/api/diff/${encodeURIComponent(slug)}/${encodeURIComponent(key)}?${params}`);
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `file diff load failed: ${r.status}`);
  return payload;
}

async function fetchRefs(slug, key) {
  const r = await fetch(`/api/refs/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`);
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `ref load failed: ${r.status}`);
  return payload;
}

async function fetchSource(slug, key, file) {
  const params = new URLSearchParams({ file, review: `${slug}/${key}` });
  const r = await fetch(`/api/source?${params}`);
  if (!r.ok) {
    const err = await r.json().catch(() => ({}));
    throw new Error(err.error || `source load failed: ${r.status}`);
  }
  return r.text();
}

async function putReview(slug, key, data) {
  const r = await fetch(`/api/review/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `save failed: ${r.status}`);
  return payload;
}

async function deleteReview(slug, key) {
  const r = await fetch(`/api/review/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "DELETE",
  });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `delete failed: ${r.status}`);
  return payload;
}

async function submitReview(slug, key, body) {
  const r = await fetch(`/api/submit/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `submit failed: ${r.status}`);
  return payload;
}

async function refreshReview(slug, key) {
  const r = await fetch(`/api/refresh/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "POST",
  });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw apiError(payload, `refresh failed: ${r.status}`);
  return payload;
}

// === Route loader ==================================================

// File-tree collapsed-folder state is per-review and persisted in localStorage
// so the user's tree shape survives reloads. Key includes slug + key (the
// same identifiers used in the route) so unrelated reviews don't share state.
function collapsedFoldersKey(slug, key) {
  return `assisted-review:collapsed-folders:${slug}:${key}`;
}

function loadCollapsedFolders(slug, key) {
  try {
    const raw = localStorage.getItem(collapsedFoldersKey(slug, key));
    if (!raw) return new Set();
    return new Set(JSON.parse(raw));
  } catch {
    return new Set();
  }
}

function saveCollapsedFolders() {
  if (!state.review) return;
  try {
    localStorage.setItem(
      collapsedFoldersKey(state.review._slug, state.review._key),
      JSON.stringify(Array.from(state.collapsedFolders)),
    );
  } catch {
    // localStorage disabled or full — collapse state stays in-memory only
  }
}

function resetNewCommentSuggestion() {
  state.newCommentSuggestionExpanded = false;
  state.newCommentSuggestionDraft = "";
}

function suppressGlobalEscapeCollapse() {
  state.suppressGlobalEscapeUntil = Date.now() + 250;
}

function shouldSuppressGlobalEscapeCollapse() {
  return Date.now() < state.suppressGlobalEscapeUntil;
}

function stopRefreshPolling() {
  if (state.refreshPollId) {
    clearInterval(state.refreshPollId);
    state.refreshPollId = null;
  }
  state.refreshStatus = null;
}

function clearFilePaneCache() {
  state.filePaneCache.forEach((entry) => entry.element.remove());
  state.filePaneCache.clear();
  state.currentFilePaneKey = null;
  focusedHunkElements = new Set();
}

async function updateRefreshStatus() {
  if (!state.review || state.route.view === "inbox") return;
  const { slug, key } = state.route;
  try {
    const status = await fetchRefreshStatus(slug, key);
    if (state.route.slug !== slug || state.route.key !== key) return;
    state.refreshStatus = status;
    state.review._stale = Boolean(status.needs_refresh);
  } catch (err) {
    if (state.route.slug !== slug || state.route.key !== key) return;
    state.refreshStatus = {
      ok: false,
      needs_refresh: false,
      reason: err?.message || "refresh status failed",
    };
  }
  renderTopbar();
}

function startRefreshPolling() {
  if (state.refreshPollId) clearInterval(state.refreshPollId);
  if (!state.review || state.route.view === "inbox") return;
  state.refreshPollId = setInterval(() => {
    if (document.visibilityState !== "hidden") {
      updateRefreshStatus();
    }
  }, 15000);
}

async function loadRoute(route) {
  const previousRoute = state.route;
  const preserveNavCursor = state.preserveNavCursorForLoad;
  state.preserveNavCursorForLoad = false;
  state.route = route;
  state.error = null;
  state.expandedComments.clear();
  state.newCommentTarget = null;
  resetNewCommentSuggestion();
  state.editingBody = null;
  state.editingSuggestion = null;
  state.suggestionDrafts.clear();
  if (
    route.view === "file"
    && (!previousRoute || previousRoute.view !== "file" || previousRoute.file !== route.file)
    && !preserveNavCursor
  ) {
    resetNavigationCursors();
  }

  try {
    if (route.view === "inbox") {
      stopRefreshPolling();
      state.review = null;
      state.source = null;
      state.fullTree = null;
      state.diffSummary = null;
      state.diffError = null;
      state.refOptions = null;
      state.diffFileCache.clear();
      clearFilePaneCache();
      state.collapsedFolders = new Set();
      state.inbox = await fetchInbox();
    } else {
      state.inbox = null;
      // Lazy-load the review only if it's not already loaded for this slug/key
      if (!state.review || state.review._slug !== route.slug || state.review._key !== route.key) {
        const data = await fetchReview(route.slug, route.key);
        data._slug = route.slug;
        data._key = route.key;
        state.review = data;
        state.refreshStatus = {
          ok: true,
          needs_refresh: Boolean(data._stale),
          mode: "initial",
        };
        state.sourceCache.clear();
        state.diffFileCache.clear();
        clearFilePaneCache();
        state.diffSummary = null;
        state.diffError = null;
        state.refOptions = null;
        state.baseDraft = data.target?.base_ref || "";
        state.fullTree = null;          // changed review → invalidate tree cache
        state.collapsedFolders = loadCollapsedFolders(route.slug, route.key);
      }
      if (!state.diffSummary && !state.diffError) {
        try {
          state.diffSummary = await fetchDiffSummary(route.slug, route.key, {
            base: state.review?.target?.base_ref || "",
          });
          state.baseDraft = state.diffSummary.base_ref || state.review?.target?.base_ref || "";
        } catch (err) {
          state.diffError = err?.message || String(err);
        }
      }
      if (!state.refOptions) {
        try {
          state.refOptions = await fetchRefs(route.slug, route.key);
          if (!state.baseDraft) state.baseDraft = state.refOptions.base_ref || "";
        } catch {
          state.refOptions = { refs: ["HEAD", "HEAD~1", "HEAD~2", "main", "origin/main"] };
        }
      }
      if (route.view === "file") {
        const [sourceResult, diffResult] = await Promise.allSettled([
          ensureSourceForFile(route.file),
          ensureDiffForFile(route.file),
        ]);
        if (sourceResult.status === "fulfilled") {
          state.source = { file: route.file, content: sourceResult.value || "" };
          state.sourceCache.set(route.file, sourceResult.value || "");
        } else {
          state.source = {
            file: route.file,
            content: "",
            unavailable: sourceResult.reason?.message || "file content not available",
          };
        }
        if (diffResult.status === "rejected") {
          state.diffFileCache.set(diffCacheKey(route.file), {
            file: route.file,
            error: diffResult.reason?.message || String(diffResult.reason),
            hunks: [],
            hunk_count: 0,
          });
        }
      } else {
        state.source = null;
      }
    }
  } catch (err) {
    state.error = String(err.message || err);
  }

  document.body.classList.toggle("inbox-mode", state.route.view === "inbox");
  renderContent();
  if (state.route.view !== "inbox") {
    startRefreshPolling();
    updateRefreshStatus();
  }
}

// === Top bar =======================================================

function renderTopbar() {
  const repoEl = document.getElementById("topbar-repo");
  const branchEl = document.getElementById("topbar-branch");
  const commitEl = document.getElementById("topbar-commit");
  const prEl = document.getElementById("topbar-pr-link");
  const staleEl = document.getElementById("topbar-stale");
  const sep1 = document.getElementById("topbar-sep-1");
  const sep2 = document.getElementById("topbar-sep-2");
  const sep3 = document.getElementById("topbar-sep-3");
  const commentNavEl = document.getElementById("topbar-comment-nav");
  const refreshBtn = document.getElementById("btn-refresh-review");
  const sendBtn = document.getElementById("btn-send-review");

  if (state.route.view === "inbox" || !state.review) {
    repoEl.textContent = "assisted-review";
    branchEl.textContent = "";
    commitEl.textContent = "";
    prEl.textContent = "";
    staleEl.hidden = true;
    sep1.hidden = sep2.hidden = sep3.hidden = true;
    commentNavEl.hidden = true;
    commentNavEl.innerHTML = "";
    refreshBtn.hidden = true;
    refreshBtn.disabled = false;
    refreshBtn.classList.remove("btn-refresh-needed");
    sendBtn.hidden = true;
    return;
  }

  const t = state.review.target || {};
  repoEl.textContent = t.repo_root ? t.repo_root.split("/").pop() : state.route.slug;
  branchEl.textContent = t.branch || "—";
  commitEl.textContent = shortSha(t.commit || t.fingerprint);
  prEl.textContent = "";
  if (t.pr_number && t.owner && t.repo) {
    // DOM-construct the link instead of innerHTML — pr_number/owner/repo
    // come straight from a YAML on disk that nothing validates at read
    // time, so an unescaped template here is an XSS sink.
    const a = document.createElement("a");
    a.href = `https://github.com/${encodeURIComponent(t.owner)}/${encodeURIComponent(t.repo)}/pull/${encodeURIComponent(t.pr_number)}`;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    a.textContent = `Review for PR #${t.pr_number}`;
    a.addEventListener("click", (e) => e.stopPropagation());
    prEl.appendChild(a);
  } else if (t.pr_number) {
    // Have a PR number but no owner/repo — older YAMLs predate the schema
    // bump. Show the number as text so submit still works (the daemon can
    // resolve owner/repo at submit time), but no clickable link.
    prEl.textContent = `Review for PR #${t.pr_number}`;
  } else {
    prEl.textContent = "Local Review";
  }
  sep1.hidden = sep2.hidden = sep3.hidden = false;
  commentNavEl.hidden = true;
  commentNavEl.innerHTML = "";

  const needsRefresh = Boolean(state.refreshStatus?.needs_refresh ?? state.review._stale);
  const refreshKnown = state.refreshStatus?.ok !== false;
  staleEl.textContent = "";
  staleEl.hidden = true;
  staleEl.title = "";

  refreshBtn.hidden = false;
  refreshBtn.disabled = !needsRefresh;
  refreshBtn.classList.toggle("btn-refresh-needed", needsRefresh);
  refreshBtn.title = needsRefresh
    ? "Refresh anchors from the current filesystem state"
    : refreshKnown
      ? "No filesystem changes detected for this review"
      : state.refreshStatus?.reason || "Refresh status unavailable";
  sendBtn.hidden = false;
  const sendBlockReason = reviewSendBlockReason();
  sendBtn.disabled = Boolean(sendBlockReason);
  const { sendableComments, notes } = submissionSummary();
  sendBtn.title = sendBlockReason || `Submit ${sendableComments} comment${sendableComments === 1 ? "" : "s"} to GitHub; ${notes} note${notes === 1 ? "" : "s"} stay local`;
  if (window.lucide) window.lucide.createIcons();
}

function currentCommentIndex(navComments) {
  if (navComments.length === 0) return -1;
  if (state.cursorCommentId) {
    const cursorIdx = navComments.findIndex((c) => c.id === state.cursorCommentId);
    if (cursorIdx !== -1) return cursorIdx;
  }
  if (state.route.view === "file") {
    const fileIdx = navComments.findIndex((c) => c.file === state.route.file);
    if (fileIdx !== -1) return fileIdx;
  }
  return 0;
}

function currentNavItems() {
  return state.navTarget === "hunks" ? navigableHunks() : navigableComments();
}

function currentNavIndex(items) {
  if (items.length === 0) return -1;
  if (state.navTarget === "hunks") {
    if (state.cursorHunk) {
      const idx = items.findIndex((h) => h.file === state.cursorHunk.file && h.index === state.cursorHunk.index);
      if (idx !== -1) return idx;
    }
    if (state.route.view === "file") {
      const fileIdx = items.findIndex((h) => h.file === state.route.file);
      if (fileIdx !== -1) return fileIdx;
    }
    return 0;
  }
  return currentCommentIndex(items);
}

function renderContextbar() {
  const bar = document.getElementById("contextbar");
  if (state.route.view === "inbox" || !state.review) {
    bar.hidden = true;
    bar.innerHTML = "";
    return;
  }

  const base = state.baseDraft || state.diffSummary?.base_ref || state.review?.target?.base_ref || "HEAD";
  const refs = state.refOptions?.refs || [];
  const items = currentNavItems();
  const idx = currentNavIndex(items);
  const navLabel = state.navTarget === "hunks" ? "Hunk" : "Thread";
  const counter = items.length === 0 ? `${navLabel} 0 / 0` : `${navLabel} ${idx + 1} / ${items.length}`;
  const disabled = items.length === 0 ? "disabled" : "";
  const diffTotals = state.diffSummary
    ? formatDiffStat({ additions: state.diffSummary.additions, deletions: state.diffSummary.deletions })
    : "";
  const baseTitle = state.diffSummary?.comparison_base
    ? `Comparing against ${shortSha(state.diffSummary.comparison_base)}`
    : state.diffError || "Diff base";

  bar.hidden = false;
  bar.innerHTML = `
    <div class="contextbar-group contextbar-base" title="${escapeHtml(baseTitle)}">
      <i data-lucide="git-compare-arrows"></i>
      <span class="contextbar-label">Base</span>
      <input id="diff-base-input" list="diff-base-options" value="${escapeHtml(base)}" spellcheck="false" aria-label="Diff base ref" title="${escapeHtml(baseTitle)}" />
      <datalist id="diff-base-options">
        ${refs.map((ref) => `<option value="${escapeHtml(ref)}"></option>`).join("")}
      </datalist>
      <button class="btn btn-icon" data-apply-base title="Apply base ref" aria-label="Apply base ref">
        <i data-lucide="check"></i>
      </button>
    </div>
    <div class="segmented diff-mode-toggle" role="group" aria-label="Diff display">
      <button class="${state.diffVisible ? "" : "active"}" data-diff-visible="0" aria-pressed="${state.diffVisible ? "false" : "true"}" title="Show source with subtle change indicators (d)">Source</button>
      <button class="${state.diffVisible ? "active" : ""}" data-diff-visible="1" aria-pressed="${state.diffVisible ? "true" : "false"}" title="Show inline diff details (d)">Diff</button>
    </div>
    <div class="segmented" role="group" aria-label="Navigation target">
      <button class="${state.navTarget === "comments" ? "active" : ""}" data-nav-target="comments" title="Navigate threads (c)">Threads</button>
      <button class="${state.navTarget === "hunks" ? "active" : ""}" data-nav-target="hunks" title="Navigate hunks (h)">Hunks</button>
    </div>
    <div class="segmented" role="group" aria-label="Thread filter">
      <button class="${state.threadFilter === "all" ? "active" : ""}" data-thread-filter="all" title="Show comments and notes">All</button>
      <button class="${state.threadFilter === "comment" ? "active" : ""}" data-thread-filter="comment" title="Show GitHub-sendable comments">Comments</button>
      <button class="${state.threadFilter === "note" ? "active" : ""}" data-thread-filter="note" title="Show local notes">Notes</button>
    </div>
    <div class="contextbar-spacer"></div>
    <div class="contextbar-diff-total">${diffTotals}</div>
    <div class="contextbar-nav">
      <button class="btn" data-prev-nav title="Previous ${state.navTarget === "hunks" ? "hunk" : "thread"} (Shift+Tab / k)" aria-label="Previous ${state.navTarget}" ${disabled}>
        <i data-lucide="chevron-up"></i>
        Prev
      </button>
      <span class="topbar-comment-nav-counter">${escapeHtml(counter)}</span>
      <button class="btn" data-next-nav title="Next ${state.navTarget === "hunks" ? "hunk" : "thread"} (Tab / j)" aria-label="Next ${state.navTarget}" ${disabled}>
        <i data-lucide="chevron-down"></i>
        Next
      </button>
    </div>
  `;
  attachContextbarHandlers(bar);
  if (window.lucide) window.lucide.createIcons();
}

function attachContextbarHandlers(root) {
  root.querySelectorAll("[data-diff-visible]").forEach((el) => {
    el.addEventListener("click", () => setDiffVisible(el.getAttribute("data-diff-visible") === "1"));
  });
  root.querySelectorAll("[data-nav-target]").forEach((el) => {
    el.addEventListener("click", () => setNavTarget(el.getAttribute("data-nav-target")));
  });
  root.querySelectorAll("[data-thread-filter]").forEach((el) => {
    el.addEventListener("click", () => setThreadFilter(el.getAttribute("data-thread-filter")));
  });
  root.querySelector("[data-prev-nav]")?.addEventListener("click", () => navigateByTarget(-1));
  root.querySelector("[data-next-nav]")?.addEventListener("click", () => navigateByTarget(+1));
  const baseInput = root.querySelector("#diff-base-input");
  if (baseInput) {
    baseInput.addEventListener("input", (e) => {
      state.baseDraft = e.target.value;
    });
    baseInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        applyBaseRef();
      }
    });
  }
  root.querySelector("[data-apply-base]")?.addEventListener("click", () => applyBaseRef());
}

// === File tree =====================================================

function renderTree() {
  const root = document.getElementById("file-tree");

  if (state.route.view === "inbox" || !state.review) {
    root.hidden = true;
    return;
  }

  root.hidden = false;
  const isReviewRoot = state.route.view === "review";

  const counts = filesWithCommentCounts();
  const filterQuery = state.treeFilter.query.toLowerCase().trim();

  const changedPaths = diffFiles().map((f) => f.file);
  const scope = state.treeFilter.scope || "comments";
  const allPaths = scope === "all" && state.fullTree
    ? unionPaths(state.fullTree.files || [], Object.keys(counts), changedPaths)
    : scope === "changed"
      ? changedPaths
      : Object.keys(counts);

  const extensionOptions = uniqueSortedExtensions(allPaths);
  state.treeFilter.extensions = (state.treeFilter.extensions || []).filter((ext) => extensionOptions.includes(ext));
  const selectedExtensions = state.treeFilter.extensions;
  const extensionQuery = normalizeExtensionInput(state.treeFilter.extensionQuery);
  const visibleExtensionOptions = extensionOptions.filter((ext) => !extensionQuery || ext.includes(extensionQuery));
  const filteredPaths = allPaths.filter((p) => {
    const matchesQuery = !filterQuery || p.toLowerCase().includes(filterQuery);
    const matchesExtension = selectedExtensions.length === 0 || selectedExtensions.includes(fileExtension(p));
    return matchesQuery && matchesExtension;
  });

  const tree = buildTreeFromFiles(filteredPaths, counts, diffFileMap());

  const filterHtml = `
    <div class="tree-filter">
      <div class="tree-filter-search">
        <i data-lucide="search"></i>
        <input type="text" id="tree-filter-query" placeholder="Filter files…" value="${escapeHtml(state.treeFilter.query)}" />
      </div>
      <details class="tree-type-filter" ${state.treeFilter.extensionMenuOpen ? "open" : ""}>
        <summary class="tree-type-filter-summary">
          <span>
            <i data-lucide="filter"></i>
            ${escapeHtml(formatExtensionSummary(selectedExtensions))}
          </span>
          <i data-lucide="chevron-down"></i>
        </summary>
        <div class="tree-type-filter-popover">
          <div class="tree-type-filter-search">
            <i data-lucide="search"></i>
            <input type="text" id="tree-extension-query" placeholder="Find type…" value="${escapeHtml(state.treeFilter.extensionQuery)}" />
          </div>
          <div class="tree-type-filter-options">
            ${visibleExtensionOptions.length
              ? visibleExtensionOptions.map((ext) => `
                <label class="tree-type-filter-option">
                  <input type="checkbox" data-toggle-tree-extension="${escapeHtml(ext)}" ${selectedExtensions.includes(ext) ? "checked" : ""} />
                  <span>.${escapeHtml(ext)}</span>
                </label>
              `).join("")
              : `<div class="tree-type-filter-empty">No file types match.</div>`}
          </div>
          ${selectedExtensions.length ? `
            <button class="tree-type-filter-clear" data-clear-tree-extensions type="button">Clear types</button>
          ` : ""}
        </div>
      </details>
      <div class="tree-filter-settings">
        <div class="tree-scope-control" role="group" aria-label="File scope">
          <button class="${scope === "comments" ? "active" : ""}" data-tree-scope="comments" type="button">Threads</button>
          <button class="${scope === "changed" ? "active" : ""}" data-tree-scope="changed" type="button">Changed</button>
          <button class="${scope === "all" ? "active" : ""}" data-tree-scope="all" type="button">All</button>
        </div>
        <label class="tree-filter-toggle ${scope === "all" ? "" : "disabled"}">
          <input type="checkbox" id="tree-filter-show-ignored" ${state.treeFilter.showIgnored ? "checked" : ""} ${scope === "all" ? "" : "disabled"} />
          Include ignored
        </label>
      </div>
    </div>
  `;

  const loadingFullTree = scope === "all" && !state.fullTree;
  const treeHtml = loadingFullTree
    ? `<div class="tree-empty">Loading file tree…</div>`
    : scope === "changed" && state.diffError
      ? `<div class="tree-empty">Diff unavailable: ${escapeHtml(state.diffError)}</div>`
    : filteredPaths.length === 0
      ? `<div class="tree-empty">No files match.</div>`
    : `<ul class="tree-node">${tree.map((n) => renderTreeNode(n)).join("")}</ul>`;

  root.innerHTML = `
    ${filterHtml}
    <div class="tree-overview">
      <div class="tree-item overview ${isReviewRoot ? "active" : ""}" data-route="review">
        <i data-lucide="layout-list"></i>
        <span>Overview</span>
        <span class="comment-pip">${visibleReviewThreads().length}</span>
      </div>
    </div>
    <div class="tree-section-label">files</div>
    ${treeHtml}
  `;
  attachTreeHandlers(root);
  if (window.lucide) window.lucide.createIcons();
}

function filesWithCommentCounts() {
  const counts = {};
  visibleReviewThreads().forEach((c) => {
    counts[c.file] = (counts[c.file] || 0) + 1;
  });
  return counts;
}

function buildTreeFromFiles(paths, commentCounts = {}, diffStats = {}) {
  const root = {};
  paths.forEach((path) => {
    const segs = path.split("/");
    let node = root;
    segs.forEach((seg, i) => {
      const isLeaf = i === segs.length - 1;
      if (isLeaf) {
        node[seg] = {
          __leaf: true,
          path,
          count: commentCounts[path] || 0,
          diff: diffStats[path] || null,
        };
      } else {
        node[seg] = node[seg] || {};
        node = node[seg];
      }
    });
  });
  return treeObjectToList(root);
}

function treeObjectToList(obj, prefix = "") {
  return Object.keys(obj)
    .sort()
    .map((name) => {
      const v = obj[name];
      if (v.__leaf) {
        return { type: "file", name, path: v.path, count: v.count, diff: v.diff };
      }
      const dirPath = prefix ? `${prefix}/${name}` : name;
      const children = treeObjectToList(v, dirPath);
      // Aggregate descendant comment counts so a collapsed folder can still
      // show users "5 comments are hiding in here" via its pip.
      const dirCount = children.reduce((sum, c) => sum + (c.type === "file" ? c.count : c.dirCount), 0);
      const additions = children.reduce((sum, c) => sum + (c.type === "file" ? Number(c.diff?.additions || 0) : c.additions), 0);
      const deletions = children.reduce((sum, c) => sum + (c.type === "file" ? Number(c.diff?.deletions || 0) : c.deletions), 0);
      return { type: "dir", name, path: dirPath, children, dirCount, additions, deletions };
    });
}

function renderTreeNode(node) {
  if (node.type === "dir") {
    const collapsed = state.collapsedFolders.has(node.path);
    const chevronIcon = collapsed ? "chevron-right" : "chevron-down";
    const folderIcon = collapsed ? "folder" : "folder-open";
    // When collapsed, surface the descendant comment count so users still see
      // "something's in there" without expanding. When expanded, child files
      // already carry their own pips so a folder pip would be redundant.
    const pip = collapsed && node.dirCount > 0
      ? `<span class="comment-pip">${node.dirCount}</span>`
      : "";
    const dirDiff = collapsed && (node.additions || node.deletions)
      ? formatDiffStat({ additions: node.additions, deletions: node.deletions })
      : "";
    const childrenHtml = collapsed
      ? ""
      : `<ul class="tree-node tree-children">${node.children.map((c) => renderTreeNode(c)).join("")}</ul>`;
    return `
      <li>
        <div class="tree-item dir" data-folder="${escapeHtml(node.path)}" title="${escapeHtml(node.path)}">
          <i data-lucide="${chevronIcon}" class="tree-chevron"></i>
          <i data-lucide="${folderIcon}"></i>
          <span class="tree-item-name">${escapeHtml(node.name)}</span>
          ${dirDiff}
          ${pip}
        </div>
        ${childrenHtml}
      </li>
    `;
  }
  const isActive = state.route.view === "file" && state.route.file === node.path;
  return `
    <li>
      <div class="tree-item file ${isActive ? "active" : ""}" data-file="${escapeHtml(node.path)}" title="${escapeHtml(node.path)}">
        <i data-lucide="file-text"></i>
        <span class="tree-item-name">${escapeHtml(node.name)}</span>
        ${formatDiffStat(node.diff)}
        ${node.count > 0 ? `<span class="comment-pip">${node.count}</span>` : ""}
      </div>
    </li>
  `;
}

function attachTreeHandlers(root) {
  root.querySelectorAll("[data-file]").forEach((el) => {
    el.addEventListener("click", () => {
      const file = el.getAttribute("data-file");
      navigate({ view: "file", slug: state.route.slug, key: state.route.key, file });
    });
  });
  root.querySelectorAll('[data-route="review"]').forEach((el) => {
    el.addEventListener("click", () => {
      navigate({ view: "review", slug: state.route.slug, key: state.route.key });
    });
  });
  root.querySelectorAll("[data-folder]").forEach((el) => {
    el.addEventListener("click", () => {
      const path = el.getAttribute("data-folder");
      if (state.collapsedFolders.has(path)) {
        state.collapsedFolders.delete(path);
      } else {
        state.collapsedFolders.add(path);
      }
      saveCollapsedFolders();
      renderTree();
    });
  });

  const filterInput = root.querySelector("#tree-filter-query");
  if (filterInput) {
    filterInput.addEventListener("input", (e) => {
      state.treeFilter.query = e.target.value;
      renderTree();
      // Restore focus + caret position after re-render
      const newInput = document.getElementById("tree-filter-query");
      if (newInput) {
        newInput.focus();
        newInput.setSelectionRange(newInput.value.length, newInput.value.length);
      }
    });
  }

  root.querySelector(".tree-type-filter")?.addEventListener("toggle", (e) => {
    state.treeFilter.extensionMenuOpen = e.target.open;
  });
  root.querySelector("#tree-extension-query")?.addEventListener("input", (e) => {
    state.treeFilter.extensionQuery = e.target.value;
    state.treeFilter.extensionMenuOpen = true;
    renderTree();
    requestAnimationFrame(() => {
      const newInput = document.getElementById("tree-extension-query");
      if (newInput) {
        newInput.focus();
        newInput.setSelectionRange(newInput.value.length, newInput.value.length);
      }
    });
  });
  root.querySelectorAll("[data-toggle-tree-extension]").forEach((el) => {
    el.addEventListener("change", (e) => {
      const ext = el.getAttribute("data-toggle-tree-extension");
      if (!ext) return;
      if (e.target.checked) {
        if (!state.treeFilter.extensions.includes(ext)) state.treeFilter.extensions.push(ext);
      } else {
        state.treeFilter.extensions = state.treeFilter.extensions.filter((item) => item !== ext);
      }
      state.treeFilter.extensionMenuOpen = true;
      renderTree();
    });
  });
  root.querySelector("[data-clear-tree-extensions]")?.addEventListener("click", () => {
    state.treeFilter.extensions = [];
    state.treeFilter.extensionQuery = "";
    state.treeFilter.extensionMenuOpen = true;
    renderTree();
  });

  root.querySelectorAll("[data-tree-scope]").forEach((el) => {
    el.addEventListener("click", async () => {
      const scope = el.getAttribute("data-tree-scope");
      if (!["comments", "changed", "all"].includes(scope)) return;
      state.treeFilter.scope = scope;
      if (scope === "all" && !state.fullTree) {
        renderTree(); // Render the loading state immediately
        try {
          state.fullTree = await fetchTree(state.route.slug, state.route.key, {
            includeIgnored: state.treeFilter.showIgnored,
          });
        } catch (err) {
          showError(err, "Could not load file tree");
          state.treeFilter.scope = "comments";
        }
      }
      renderTree();
    });
  });

  const showIgnoredToggle = root.querySelector("#tree-filter-show-ignored");
  if (showIgnoredToggle) {
    showIgnoredToggle.addEventListener("change", async (e) => {
      state.treeFilter.showIgnored = e.target.checked;
      if (state.treeFilter.scope === "all") {
        state.fullTree = null;
        renderTree();
        try {
          state.fullTree = await fetchTree(state.route.slug, state.route.key, {
            includeIgnored: state.treeFilter.showIgnored,
          });
        } catch (err) {
          showError(err, "Could not load ignored files");
          state.treeFilter.showIgnored = false;
        }
      }
      renderTree();
    });
  }
}

// === Content rendering =============================================

function renderContent() {
  // Chrome reflects the navigation cursor counter — keep it in sync with
  // every content render so Tab / button clicks update the tree rail.
  renderTopbar();
  renderContextbar();
  renderTree();
  const content = document.getElementById("content");
  if (state.route.view !== "file") {
    rememberCurrentFilePaneScroll(content);
    state.currentFilePaneKey = null;
  }
  if (state.error) {
    content.innerHTML = `<div class="error-banner">${escapeHtml(state.error)}</div>`;
    return;
  }
  if (state.route.view === "inbox") return renderInbox();
  if (!state.review) {
    content.innerHTML = `<div class="loading">Loading review…</div>`;
    return;
  }
  if (state.route.view === "file") return renderFileView();
  return renderReviewOverview();
}

// --- Inbox ---

function renderInbox() {
  const content = document.getElementById("content");
  const reviews = state.inbox?.reviews || [];

  if (reviews.length === 0) {
    content.innerHTML = `
      <div class="inbox">
        <div class="inbox-header">
          <h1>Reviews</h1>
        </div>
        <div class="inbox-welcome">
          <h2>No reviews yet</h2>
          <p>Run <code>/assisted-review</code> in any repo to generate one. Reviews land in <code>~/.reviews/&lt;repo-slug&gt;/</code> and will appear here as soon as they're written. Background jobs that produce reviews show up the same way.</p>
        </div>
      </div>
    `;
    return;
  }

  const buckets = bucketReviews(reviews);
  const tabs = [
    { id: "needs_triage", label: "Needs triage", reviews: buckets.needs_triage },
    { id: "iterating", label: "Iterating", reviews: buckets.iterating },
    { id: "done", label: "Done", reviews: buckets.done },
    { id: "stale", label: "Stale", reviews: buckets.stale },
  ];

  const activeTabReviews = tabs.find((t) => t.id === state.inboxFilter)?.reviews || [];
  const visible = state.showStale
    ? activeTabReviews
    : activeTabReviews.filter((r) => !r.stale || state.inboxFilter === "stale");

  const tableHtml = visible.length === 0
    ? `<div class="inbox-empty">No reviews in this bucket. Run <code>/assisted-review</code> to make one.</div>`
    : `
      <table class="inbox-table">
        <thead>
          <tr>
            <th>Repo</th>
            <th>Branch</th>
            <th>SHA</th>
            <th>Severity</th>
            <th>Age</th>
            <th>PR</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${visible.map(renderInboxRow).join("")}
        </tbody>
      </table>
    `;

  content.innerHTML = `
    <div class="inbox">
      <div class="inbox-header">
        <h1>Reviews</h1>
        <div class="meta">${reviews.length} total · ${buckets.needs_triage.length} need triage</div>
      </div>
      <div class="inbox-tabs">
        ${tabs.map((t) => `
          <button class="inbox-tab ${state.inboxFilter === t.id ? "active" : ""}" data-tab="${t.id}">
            ${t.label}<span class="inbox-tab-count">${t.reviews.length}</span>
          </button>
        `).join("")}
        <label class="show-stale-toggle">
          <input type="checkbox" id="show-stale" ${state.showStale ? "checked" : ""}>
          Show stale
        </label>
      </div>
      ${tableHtml}
    </div>
  `;

  content.querySelectorAll("[data-tab]").forEach((el) => {
    el.addEventListener("click", () => {
      state.inboxFilter = el.getAttribute("data-tab");
      renderInbox();
    });
  });
  content.querySelector("#show-stale")?.addEventListener("change", (e) => {
    state.showStale = e.target.checked;
    renderInbox();
  });
  content.querySelectorAll(".inbox-row").forEach((row) => {
    row.addEventListener("click", (e) => {
      if (e.target.closest(".inbox-delete")) return;
      const slug = row.getAttribute("data-slug");
      const key = row.getAttribute("data-key");
      navigate({ view: "review", slug, key });
    });
  });
  content.querySelectorAll(".inbox-delete").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      const slug = btn.getAttribute("data-slug");
      const key = btn.getAttribute("data-key");
      if (!confirm(`Delete review ${key}? The file will be removed.`)) return;
      try {
        await deleteReview(slug, key);
        showToast("Deleted review", { kind: "success" });
        loadRoute(state.route);
      } catch (err) {
        showError(err, "Delete failed");
      }
    });
  });
  if (window.lucide) window.lucide.createIcons();
}

function bucketReviews(reviews) {
  const out = { needs_triage: [], iterating: [], done: [], stale: [] };
  reviews.forEach((r) => {
    if (r.stale) {
      out.stale.push(r);
      return;
    }
    if (r.has_unanswered_user) {
      out.iterating.push(r);
      return;
    }
    const sc = r.status_counts || {};
    if ((sc.open || 0) > 0) {
      out.needs_triage.push(r);
    } else {
      out.done.push(r);
    }
  });
  return out;
}

function renderInboxRow(r) {
  const sev = r.severity_counts || {};
  const pip = (color, count) =>
    Array(count).fill(0).map(() => `<span class="severity-pip" style="background:${color}"></span>`).join("");

  const pipsHtml = `
    <span class="severity-pips">
      ${sev.critical ? `<span class="severity-pip-group">${pip("var(--sev-critical)", sev.critical)}</span>` : ""}
      ${sev.high ? `<span class="severity-pip-group">${pip("var(--sev-high)", sev.high)}</span>` : ""}
      ${sev.medium ? `<span class="severity-pip-group">${pip("var(--sev-medium)", sev.medium)}</span>` : ""}
      ${sev.low ? `<span class="severity-pip-group">${pip("var(--sev-low)", sev.low)}</span>` : ""}
      ${sev.info ? `<span class="severity-pip-group">${pip("var(--sev-info)", sev.info)}</span>` : ""}
    </span>
  `;

  const replies = r.has_user_reply ? `<span class="reply-flag">reply</span>` : "";
  const stale = r.stale ? `<span class="stale-flag">stale</span>` : "";
  const threadSummary = `
    <span class="thread-count-summary">
      ${Number(r.comment_count || 0)} comments
      ${Number(r.note_count || 0) ? `· ${Number(r.note_count || 0)} notes` : ""}
    </span>
  `;

  return `
    <tr class="inbox-row ${r.stale ? "stale" : ""}" data-slug="${r.slug}" data-key="${r.key}">
      <td><span class="repo">${escapeHtml(r.repo_name)}</span> ${stale}</td>
      <td><span class="branch">${escapeHtml(r.branch || "—")}</span></td>
      <td><span class="sha">${escapeHtml(r.short_sha)}</span></td>
      <td>${pipsHtml} ${threadSummary} ${replies}</td>
      <td><span class="age">${relativeAge(r.modified)}</span></td>
      <td>${r.pr_number ? `<span class="pr">#${escapeHtml(r.pr_number)}</span>` : `<span class="pr none">—</span>`}</td>
      <td><button class="inbox-delete" title="Delete review" data-slug="${r.slug}" data-key="${r.key}"><i data-lucide="trash-2"></i></button></td>
    </tr>
  `;
}

// --- Per-review overview ---

function renderOverviewCard(kind) {
  const block = ensureOverviewBlock(kind);
  const id = overviewId(kind);
  const idSafe = escapeHtml(id);
  const isSummary = kind === "summary";
  const type = isSummary ? "comment" : "note";
  const title = isSummary ? "GitHub review summary" : "Reviewer note";
  const isEditing = state.editingBody === id;
  const body = block.body || "";
  const bodyHtml = isEditing
    ? `
      <textarea class="comment-body-edit" data-edit-body="${idSafe}" autofocus>${escapeHtml(body)}</textarea>
      <div class="comment-editor-preview markdown-body" data-markdown-preview-for="${idSafe}">${renderMarkdown(body)}</div>
      <div class="comment-body-edit-hint">Cmd/Ctrl+Enter to save · Esc to cancel</div>
    `
    : body.trim()
      ? `<div class="comment-body markdown-body">${renderMarkdown(body)}</div>`
      : `<div class="comment-body empty">No ${isSummary ? "summary" : "note"} yet.</div>`;
  const editButton = isEditing ? "" : `
    <button class="comment-menu-trigger" data-edit-target="${idSafe}" title="Edit ${escapeHtml(title)}" aria-label="Edit ${escapeHtml(title)}" type="button">
      <i data-lucide="pencil"></i>
    </button>
  `;

  return `
    <div class="comment-card overview-card ${type}" data-comment-card="${idSafe}">
      <div class="comment-header">
        ${renderAuthorBadge(block.author || "ai")}
        ${renderMetaChip("type", type, title)}
        <span class="comment-header-spacer"></span>
        ${editButton}
      </div>
      ${bodyHtml}
      ${renderReplies({ id, replies: block.replies })}
      <div class="comment-actions">
        <div class="spacer"></div>
        <button class="btn" data-add-reply="${idSafe}">
          <i data-lucide="message-square-plus"></i>
          Add reply
        </button>
      </div>
    </div>
  `;
}

function renderReviewOverview() {
  const r = state.review.review;
  const t = state.review.target;
  const grouped = {};
  const threads = visibleReviewThreads();
  threads.forEach((c) => {
    if (!grouped[c.file]) grouped[c.file] = [];
    grouped[c.file].push(c);
  });
  const counts = threadCounts(threads);

  const groupsHtml = Object.entries(grouped).map(([file, threads]) => `
    <div class="file-group">
      <div class="file-group-header" data-file="${escapeHtml(file)}">
        <i data-lucide="file-text"></i>
        <strong>${escapeHtml(file)}</strong>
        <span>·</span>
        <span>${threads.length} ${threads.length === 1 ? "thread" : "threads"}</span>
      </div>
      <div class="file-group-cards">
        ${threads
          .sort((a, b) => severityOrder(a.severity) - severityOrder(b.severity) || confidenceOrder(a.confidence) - confidenceOrder(b.confidence))
          .map((c) => renderCommentCard(c, { withLineRef: true, fileLanguage: detectLanguage(file) }))
          .join("")}
      </div>
    </div>
  `).join("");

  document.getElementById("content").innerHTML = `
    <div class="overview-header">
      <h1>${escapeHtml(shortSha(t.commit))} · ${escapeHtml(t.branch || "—")}</h1>
      <div class="meta">${escapeHtml(t.repo_root || "")}</div>
    </div>

    <div class="overview-cards">
      ${renderOverviewCard("summary")}
      ${renderOverviewCard("note")}
    </div>

    <div class="overview-comments-label">Review event · ${escapeHtml(r.event)}</div>
    <div class="overview-comments-label">${counts.comments} comments · ${counts.notes} notes across ${Object.keys(grouped).length} files</div>
    ${groupsHtml || `<div class="inbox-empty">No threads match the current filter.</div>`}
  `;

  attachContentHandlers();
  if (window.lucide) window.lucide.createIcons();
}

// --- Per-file view ---

function renderFileView() {
  const content = document.getElementById("content");
  const filePath = state.route.file;
  if (!canCacheFilePane()) {
    rememberCurrentFilePaneScroll(content);
    state.currentFilePaneKey = null;
    content.innerHTML = renderFileViewHtml(filePath);
    attachContentHandlers();
    if (window.lucide) window.lucide.createIcons();
    return;
  }

  const cacheKey = filePaneCacheKey(filePath);
  rememberCurrentFilePaneScroll(content);
  let entry = state.filePaneCache.get(cacheKey);
  if (!entry) {
    const element = document.createElement("div");
    element.className = "file-pane-cache-entry";
    element.dataset.filePaneKey = cacheKey;
    element.innerHTML = renderFileViewHtml(filePath);
    entry = { key: cacheKey, file: filePath, element, scrollTop: 0 };
    state.filePaneCache.set(cacheKey, entry);
    content.replaceChildren(element);
    state.currentFilePaneKey = cacheKey;
    attachContentHandlers();
    if (window.lucide) window.lucide.createIcons();
  } else {
    content.replaceChildren(entry.element);
    state.currentFilePaneKey = cacheKey;
  }
  content.scrollTop = entry.scrollTop || 0;
  syncExpandedCommentRows(entry.element);
  applyDiffVisibility(state.diffVisible);
  syncFocusedHunkRows();
}

function canCacheFilePane() {
  return !state.newCommentTarget && !state.editingBody && !state.editingSuggestion;
}

function filePaneCacheKey(filePath) {
  const slug = state.review?._slug || state.route.slug || "";
  const key = state.review?._key || state.route.key || "";
  const base = state.diffSummary?.base_ref || state.review?.target?.base_ref || "";
  return [slug, key, base, state.threadFilter, filePath].join("\0");
}

function rememberCurrentFilePaneScroll(content = document.getElementById("content")) {
  if (!state.currentFilePaneKey || !content) return;
  const entry = state.filePaneCache.get(state.currentFilePaneKey);
  if (entry && content.contains(entry.element)) entry.scrollTop = content.scrollTop;
}

function renderFileViewHtml(filePath) {
  const language = detectLanguage(filePath, state.source?.content);
  const diffDetail = state.diffFileCache.get(diffCacheKey(filePath)) || diffStatForFile(filePath);

  const sourceUnavailable = state.source?.unavailable;
  const source = state.source?.content || "";
  const lines = source ? source.split("\n") : [];
  const fileComments = visibleReviewThreads()
    .filter((c) => c.file === filePath)
    .sort((a, b) => commentLineRange(a)[0] - commentLineRange(b)[0]);

  const { threadsAtLine, threadsEndingAtLine, rangedSpanLines } = commentLineMaps(fileComments);
  const overlay = diffOverlayForSource(diffDetail?.hunks || [], lines.length);
  const diffVisible = state.diffVisible;
  const lineNumberDigits = diffLineNumberDigits(diffDetail?.hunks || [], lines.length);
  const tableStyle = `style="--line-number-text-width:${lineNumberDigits}ch;--line-number-gutter-width:calc(${lineNumberDigits}ch + 30px)"`;
  const focusedHunkIndex = state.cursorHunk?.file === filePath ? state.cursorHunk.index : null;
  const renderDeletedRows = (items, virtualMarkerHtml = "") => items
    .map((row) => renderDeletedDiffRow(row, language, focusedHunkIndex, virtualMarkerHtml))
    .join("");
  const renderDeletionSummaries = (items, virtualMarkerHtml = "") => items
    .map((summary) => renderDeletionSummaryRow(summary, focusedHunkIndex, virtualMarkerHtml))
    .join("");

  const rows = lines.map((lineText, idx) => {
    const lineNum = idx + 1;
    const covering = threadsAtLine.get(lineNum) || [];
    const ending = threadsEndingAtLine.get(lineNum) || [];
    const inRange = rangedSpanLines.has(lineNum);
    const hunkIndex = overlay.hunkStarts.get(lineNum) ?? overlay.fallbackHunkStarts.get(lineNum);
    const hunkMember = overlay.hunkMembers.get(lineNum);
    const changed = overlay.changedLines.has(lineNum);

    let markerHtml = "";
    const primary = covering[0];
    const virtualMarkerHtml = virtualRangeMarkerHtml(primary, lineNum);
    if (primary) {
      const [s, e] = commentLineRange(primary);
      const color = threadMarkerColor(primary);
      const dot = s === e && lineNum === s
        ? `<span class="dot" style="background:${color}"></span>`
        : "";
      const rail = s !== e
        ? `<span class="bar" style="background:${color}"></span>`
        : "";
      markerHtml = `${rail}${dot}`;
    }

    const markerClass = primary ? `gutter-marker thread-marker-cell has-marker ${threadType(primary)} ${rangeMarkerClass(primary, lineNum)}`
      : inRange ? `gutter-marker thread-marker-cell range-mid`
        : "gutter-marker thread-marker-cell";
    const isUncommented = !primary && !inRange;
    const rowClass = [
      primary ? "has-comment" : "",
      inRange && !primary ? "range-spanned" : "",
      changed ? "diff-added-line diff-indicator-line" : "",
      hunkMember === focusedHunkIndex ? "nav-focus nav-focus-hunk" : "",
      isUncommented ? "uncommented" : "",
    ].filter(Boolean).join(" ");
    const codeHtml = renderHighlightedLine(lineText, language);
    const gutterDataAttr = primary
      ? `data-comment-id="${escapeHtml(primary.id)}"`
      : `data-add-line="${lineNum}"`;
    const hunkAttr = hunkIndex !== undefined ? `data-hunk-index="${hunkIndex}"` : "";
    const hunkMemberAttr = hunkMember !== undefined ? `data-hunk-member="${hunkMember}"` : "";
    const threadLineAttr = primary ? `data-thread-line-id="${escapeHtml(primary.id)}"` : "";

    let html = `
      ${renderDeletionSummaries(overlay.deletionSummariesBeforeLine.get(lineNum) || [], virtualMarkerHtml)}
      ${renderDeletedRows(overlay.beforeLine.get(lineNum) || [], virtualMarkerHtml)}
      <tr class="${rowClass}" ${hunkAttr} ${hunkMemberAttr} data-source-line="${lineNum}" ${threadLineAttr}>
        <td class="gutter-num ${changed ? "changed" : ""}"><span class="line-number-text">${lineNum}</span></td>
        <td class="${markerClass}" ${gutterDataAttr}>${markerHtml}</td>
        <td class="code-cell">${codeHtml}</td>
      </tr>
    `;

    ending.forEach((c) => {
      const hiddenAttr = state.expandedComments.has(c.id) ? "" : "hidden";
      html += `
        <tr class="comment-row" data-comment-row-id="${escapeHtml(c.id)}" ${hiddenAttr}>
          <td colspan="3"><div class="comment-row-inner">${renderCommentCard(c, { fileLanguage: language, sourceLines: lines })}</div></td>
        </tr>
      `;
    });

    // New-comment form rendered inline below the clicked line
    if (state.newCommentTarget && state.newCommentTarget.file === filePath && state.newCommentTarget.line === lineNum) {
      html += `
        <tr class="comment-row">
          <td colspan="3"><div class="comment-row-inner">${renderNewCommentForm()}</div></td>
        </tr>
      `;
    }

    return html;
  }).join("") + renderDeletedRows(overlay.afterAll) + renderDeletionSummaries(overlay.deletionSummariesAfterAll);

  const hasDiffOnlyRows = overlay.afterAll.length > 0 || overlay.deletionSummariesAfterAll.length > 0;
  const emptyHtml = sourceUnavailable && !hasDiffOnlyRows
    ? `<div class="file-unavailable">${escapeHtml(sourceUnavailable)}. Turn diff on to inspect deleted or unreadable changed lines.</div>`
    : "";
  const diffOnlyRows = sourceUnavailable && hasDiffOnlyRows
    ? `<table class="code-table full-source-table ${diffVisible ? "diff-overlay-on" : "diff-overlay-off"}" ${tableStyle}><tbody>${renderDeletedRows(overlay.afterAll)}${renderDeletionSummaries(overlay.deletionSummariesAfterAll)}</tbody></table>`
    : "";
  const statHtml = formatDiffStat(diffStatForFile(filePath) || diffDetail);
  const counts = threadCounts(fileComments);

  return `
    <div class="code-pane">
      <div class="code-header">
        <i data-lucide="file-text"></i>
        <strong>${escapeHtml(filePath)}</strong>
        <span class="lang-badge">${language || "auto"}</span>
        ${statHtml}
        <span class="code-comment-count">${counts.comments} comments · ${counts.notes} notes</span>
      </div>
      <div class="code-table-scroll">
        ${emptyHtml || diffOnlyRows || `<table class="code-table full-source-table ${diffVisible ? "diff-overlay-on" : "diff-overlay-off"}" ${tableStyle}><tbody>${rows}</tbody></table>`}
      </div>
    </div>
  `;
}

function commentLineMaps(fileComments) {
  const threadsAtLine = new Map();
  const threadsEndingAtLine = new Map();
  const rangedSpanLines = new Set();
  fileComments.forEach((c) => {
    const [s, e] = commentLineRange(c);
    if (!threadsEndingAtLine.has(e)) threadsEndingAtLine.set(e, []);
    threadsEndingAtLine.get(e).push(c);
    for (let i = s; i <= e; i++) rangedSpanLines.add(i);
    for (let i = s; i <= e; i++) {
      if (!threadsAtLine.has(i)) threadsAtLine.set(i, []);
      threadsAtLine.get(i).push(c);
    }
  });
  return { threadsAtLine, threadsEndingAtLine, rangedSpanLines };
}

function rangeMarkerClass(c, lineNum) {
  const [s, e] = commentLineRange(c);
  if (s === e) return "range-only";
  if (lineNum === s) return "range-start";
  if (lineNum === e) return "range-end";
  return "range-mid";
}

function virtualRangeMarkerHtml(c, lineNum) {
  if (!c) return "";
  const [s, e] = commentLineRange(c);
  if (s === e || lineNum <= s || lineNum > e) return "";
  return `<span class="bar" style="background:${threadMarkerColor(c)}"></span>`;
}

function diffOverlayForSource(hunks, lineCount) {
  const beforeLine = new Map();
  const afterAll = [];
  const changedLines = new Set();
  const deletionSummariesBeforeLine = new Map();
  const deletionSummariesAfterAll = [];
  const hunkStarts = new Map();
  const fallbackHunkStarts = new Map();
  const hunkMembers = new Map();
  let deletionGroup = 0;

  function addBefore(lineNum, row) {
    if (!beforeLine.has(lineNum)) beforeLine.set(lineNum, []);
    beforeLine.get(lineNum).push(row);
  }

  function addDeletionSummary(lineNum, summary) {
    if (!deletionSummariesBeforeLine.has(lineNum)) deletionSummariesBeforeLine.set(lineNum, []);
    deletionSummariesBeforeLine.get(lineNum).push(summary);
  }

  function addMember(lineNum, hunkIndex) {
    if (!Number.isInteger(lineNum)) return;
    if (!hunkMembers.has(lineNum)) hunkMembers.set(lineNum, hunkIndex);
  }

  hunks.forEach((hunk, hunkIndex) => {
    let pendingDeletes = [];
    let hunkStarted = false;
    const markHunkStart = () => {
      if (hunkStarted) return false;
      hunkStarted = true;
      return true;
    };
    const flushDeletes = (targetLine) => {
      if (!pendingDeletes.length) return;
      const fallbackLine = Math.min(
        lineCount + 1,
        Math.max(1, Number(hunk.new_start || 1) + Number(hunk.new_lines || 0)),
      );
      const insertLine = Number.isInteger(targetLine) ? targetLine : fallbackLine;
      const startsHunk = !hunkStarted;
      const groupId = deletionGroup;
      deletionGroup += 1;
      pendingDeletes = pendingDeletes.map((row, offset) => ({
        ...row,
        deletionGroup: groupId,
        hunkStart: startsHunk && offset === 0 ? markHunkStart() : false,
      }));
      if (startsHunk && insertLine <= lineCount) {
        fallbackHunkStarts.set(insertLine, hunkIndex);
      }
      const summary = {
        count: pendingDeletes.length,
        deletionGroup: groupId,
        hunkIndex,
        hunkStart: startsHunk,
      };
      if (insertLine <= lineCount) {
        pendingDeletes.forEach((row) => addBefore(insertLine, row));
        addDeletionSummary(insertLine, summary);
      } else {
        afterAll.push(...pendingDeletes);
        deletionSummariesAfterAll.push(summary);
      }
      pendingDeletes = [];
    };

    (hunk.lines || []).forEach((line) => {
      if (line.kind === "del") {
        pendingDeletes.push({
          kind: "del",
          oldLine: line.old_line,
          text: line.text || "",
          hunkIndex,
          hunkStart: false,
        });
        return;
      }

      const newLine = line.new_line;
      if (Number.isInteger(newLine)) {
        flushDeletes(newLine);
        if (!hunkStarted) {
          hunkStarts.set(newLine, hunkIndex);
          hunkStarted = true;
        }
        addMember(newLine, hunkIndex);
        if (line.kind === "add") changedLines.add(newLine);
      }
    });
    flushDeletes(null);
  });

  return {
    beforeLine,
    afterAll,
    changedLines,
    deletionSummariesBeforeLine,
    deletionSummariesAfterAll,
    hunkStarts,
    fallbackHunkStarts,
    hunkMembers,
  };
}

function diffLineNumberDigits(hunks, lineCount) {
  let maxLine = Math.max(1, Number(lineCount) || 1);
  let maxMarkerChars = String(maxLine).length;
  (hunks || []).forEach((hunk) => {
    const oldEnd = Number(hunk.old_start || 0) + Math.max(0, Number(hunk.old_lines || 0) - 1);
    const newEnd = Number(hunk.new_start || 0) + Math.max(0, Number(hunk.new_lines || 0) - 1);
    maxLine = Math.max(maxLine, oldEnd, newEnd);
    let deletedRun = 0;
    const flushDeletedRun = () => {
      if (deletedRun > 0) {
        maxMarkerChars = Math.max(maxMarkerChars, String(deletedRun).length + 1);
        deletedRun = 0;
      }
    };
    (hunk.lines || []).forEach((line) => {
      if (line.kind === "del") {
        deletedRun += 1;
      } else {
        flushDeletedRun();
      }
      if (Number.isInteger(line.old_line)) maxLine = Math.max(maxLine, line.old_line);
      if (Number.isInteger(line.new_line)) maxLine = Math.max(maxLine, line.new_line);
    });
    flushDeletedRun();
  });
  return Math.max(2, String(maxLine).length, maxMarkerChars);
}

function renderDeletionSummaryRow(summary, focusedHunkIndex, virtualMarkerHtml = "") {
  const label = `-${summary.count}`;
  const title = `${summary.count} deleted ${summary.count === 1 ? "line" : "lines"}. Turn diff on to view.`;
  const hunkAttr = summary.hunkStart ? `data-hunk-index="${summary.hunkIndex}"` : "";
  const focusClass = summary.hunkIndex === focusedHunkIndex ? "nav-focus nav-focus-hunk" : "";
  return `
    <tr class="source-virtual-line diff-deletion-summary ${focusClass}" ${hunkAttr} data-hunk-member="${summary.hunkIndex}">
      <td class="gutter-num deletion-summary" title="${escapeHtml(title)}">
        <button class="deletion-count-marker" type="button" data-show-deletion-group="${summary.deletionGroup}" data-show-deletion-hunk="${summary.hunkIndex}" aria-label="${escapeHtml(title)}" title="${escapeHtml(title)}">${escapeHtml(label)}</button>
      </td>
      <td class="gutter-marker diff-virtual-gutter">${virtualMarkerHtml}</td>
      <td class="code-cell deletion-summary-cell" title="${escapeHtml(title)}"></td>
    </tr>
  `;
}

function renderDeletedDiffRow(row, language, focusedHunkIndex, virtualMarkerHtml = "") {
  const hunkAttr = row.hunkStart ? `data-hunk-index="${row.hunkIndex}"` : "";
  const focusClass = row.hunkIndex === focusedHunkIndex ? "nav-focus nav-focus-hunk" : "";
  return `
    <tr class="source-virtual-line diff-deleted-line ${focusClass}" ${hunkAttr} data-hunk-member="${row.hunkIndex}" data-deletion-group="${row.deletionGroup}" data-deleted-old-line="${row.oldLine || ""}">
      <td class="gutter-num deleted"><span class="line-diff-mark deletion">−</span><span class="line-number-text">${row.oldLine || ""}</span></td>
      <td class="gutter-marker diff-virtual-gutter">${virtualMarkerHtml}</td>
      <td class="code-cell">${renderHighlightedLine(row.text || "", language)}</td>
    </tr>
  `;
}

function threadMarkerColor(c) {
  return isNoteThread(c) ? "var(--thread-note)" : "var(--thread-comment)";
}

// --- New comment form ---

function renderNewCommentForm() {
  const t = state.newCommentTarget;
  const language = detectLanguage(t.file, state.source?.content);
  const isNote = state.newThreadType === "note";
  const originalSuggestion = originalTextForNewComment();
  const initialSuggestion = state.newCommentSuggestionDraft || originalSuggestion;
  const suggestionHtml = !isNote && state.newCommentSuggestionExpanded
    ? `
      <div class="comment-suggestion new-comment-suggestion">
        <div class="comment-suggestion-label">
          <i data-lucide="lightbulb"></i>
          Suggested change
          <button class="suggestion-edit-btn" data-collapse-new-suggestion title="Remove suggested change draft" aria-label="Remove suggested change draft">
            <i data-lucide="x"></i>
          </button>
        </div>
        <textarea id="new-suggestion" class="suggestion" data-suggestion-language="${escapeHtml(language || "")}" placeholder="Optional suggested change. Raw code — no fences. Replaces the line${t.isRange ? "s" : ""} above.">${escapeHtml(initialSuggestion)}</textarea>
        <div class="suggestion-warning" id="new-suggestion-warning" hidden></div>
        <div class="suggestion-preview" id="new-suggestion-preview"></div>
      </div>
    `
    : isNote ? "" : `
      <button class="btn btn-suggestion-add" data-expand-new-suggestion type="button">
        <i data-lucide="lightbulb"></i>
        Add suggested change
      </button>
    `;
  return `
    <div class="new-comment-form" data-new-comment-form>
      <div class="form-row">
        <span class="comment-line-ref">L${t.line}${t.isRange && t.endLine ? `–${t.endLine}` : ""}</span>
        <div class="segmented thread-kind-toggle" role="group" aria-label="Thread type">
          <button class="${state.newThreadType === "comment" ? "active" : ""}" data-new-thread-type="comment" type="button">Comment</button>
          <button class="${state.newThreadType === "note" ? "active" : ""}" data-new-thread-type="note" type="button">Note</button>
        </div>
        <label class="range-toggle">
          <input type="checkbox" id="new-range-toggle" ${t.isRange ? "checked" : ""} />
          Range
        </label>
        ${t.isRange ? `<span class="comment-line-ref">to line</span><input type="number" id="new-end-line" min="${t.line}" value="${t.endLine || t.line}" />` : ""}
        <button class="comment-close" data-cancel-new title="Close (Esc)"><i data-lucide="x"></i></button>
      </div>
      <div class="form-row">
        <select id="new-severity">
          <option value="critical">critical</option>
          <option value="high">high</option>
          <option value="medium" selected>medium</option>
          <option value="low">low</option>
          <option value="info">info</option>
        </select>
        <select id="new-confidence">
          <option value="high">high confidence</option>
          <option value="medium" selected>medium confidence</option>
          <option value="low">low confidence</option>
        </select>
        <input type="text" id="new-category" placeholder="${isNote ? "category (context, risk, question, …)" : "category (correctness, security, perf, style, …)"}" />
      </div>
      <textarea id="new-body" placeholder="${isNote ? "Note body. Local-only Markdown for reviewer context." : "Comment body. Markdown — backticks for inline code."}"></textarea>
      <div class="comment-editor-preview markdown-body" id="new-body-preview"></div>
      ${suggestionHtml}
      <div class="form-actions">
        <button class="btn btn-primary" data-save-new>
          <i data-lucide="plus"></i>
          Add ${isNote ? "note" : "comment"}
        </button>
      </div>
    </div>
  `;
}

function nextCommentId() {
  const ids = reviewThreads().map((c) => c.id);
  let max = 0;
  ids.forEach((id) => {
    const m = /^rev-(\d+)$/.exec(id);
    if (m) max = Math.max(max, parseInt(m[1], 10));
  });
  return `rev-${String(max + 1).padStart(3, "0")}`;
}

// --- Comment card ---

function authorKind(author) {
  return author === "ai" ? "ai" : "user";
}

function authorLabel(author) {
  return author === "ai" ? "AI" : "User";
}

function renderAuthorBadge(author, className = "author-badge") {
  const kind = authorKind(author);
  const label = authorLabel(author);
  const icon = kind === "ai" ? "bot" : "user";
  return `
    <span class="${className} ${kind}" title="${escapeHtml(label)}" aria-label="${escapeHtml(label)}">
      <i data-lucide="${icon}"></i>
      <span class="visually-hidden">${escapeHtml(label)}</span>
    </span>
  `;
}

function renderMetaChip(kind, value, label = value) {
  const safeKind = escapeHtml(kind);
  const safeValue = escapeHtml(value || "");
  const safeLabel = escapeHtml(label || value || "");
  const valueClass = kind === "category" ? "" : ` ${safeValue}`;
  return `
    <span class="metadata-chip ${safeKind}-chip${valueClass}">
      <i data-lucide="${chipIcon(kind, value)}"></i>
      ${safeLabel}
    </span>
  `;
}

function renderStatusDropdown(c, idSafe) {
  const status = STATUS_OPTIONS.some((option) => option.value === c.status) ? c.status : "open";
  const statusSafe = escapeHtml(status);
  return `
    <details class="status-menu">
      <summary class="status-button status-chip ${statusSafe}" title="Change status">
        <i data-lucide="${chipIcon("status", status)}"></i>
        Status: ${escapeHtml(humanStatus(status))}
        <i data-lucide="chevron-down"></i>
      </summary>
      <div class="status-menu-popover">
        ${STATUS_OPTIONS.map((option) => `
          <button class="status-menu-item ${status === option.value ? "active" : ""}" data-set-status="${idSafe}" data-status-value="${escapeHtml(option.value)}" type="button">
            <i data-lucide="${option.icon}"></i>
            ${escapeHtml(option.label)}
          </button>
        `).join("")}
      </div>
    </details>
  `;
}

function renderCommentActionsMenu(c, idSafe, anchorCurrent) {
  const hasBody = Boolean((c.body || "").trim());
  const suggestionAction = isNoteThread(c) ? "" : hasSuggestion(c)
    ? `
      <button class="comment-menu-item" data-edit-suggestion-target="${idSafe}" ${anchorCurrent ? "" : "disabled"} type="button">
        <i data-lucide="lightbulb"></i>
        Edit suggestion
      </button>
      <button class="comment-menu-item danger" data-delete-suggestion="${idSafe}" type="button">
        <i data-lucide="trash-2"></i>
        Delete suggestion
      </button>
    `
    : `
      <button class="comment-menu-item" data-edit-suggestion-target="${idSafe}" ${anchorCurrent ? "" : "disabled"} type="button">
        <i data-lucide="lightbulb"></i>
        Add suggestion
      </button>
    `;
  const bodyAction = hasBody ? "Edit thread" : "Add thread";
  return `
    <details class="comment-menu">
      <summary class="comment-menu-trigger" title="Comment actions" aria-label="Comment actions">
        <i data-lucide="pencil"></i>
      </summary>
      <div class="comment-menu-popover">
        <button class="comment-menu-item" data-edit-target="${idSafe}" type="button">
          <i data-lucide="pencil"></i>
          ${bodyAction}
        </button>
        ${suggestionAction}
      </div>
    </details>
  `;
}

function renderCommentCard(c, opts = {}) {
  const [s, e] = commentLineRange(c);
  const lineRef = s === e ? `L${s}` : `L${s}–${e}`;
  const type = threadType(c);
  const isNote = type === "note";
  const sev = c.severity || "info";
  const confidence = c.confidence || "medium";
  const author = c.author || "ai";
  const anchorStatus = c.anchor_status || "current";
  const anchorCurrent = anchorStatus === "current" || anchorStatus === "moved";
  const language = opts.fileLanguage || detectLanguage(c.file);
  const hasBody = Boolean((c.body || "").trim());
  const sendBlockReason = commentSendBlockReason(c);

  // Severity / status / id are *expected* to be enum / pattern values, but
  // validate.py is only run at generation time — a malicious YAML written
  // into ~/.reviews/ by some other tool could carry any string. Escape
  // every interpolation that lands in attributes or text content.
  const anchorSafe = escapeHtml(anchorStatus);
  const idSafe = escapeHtml(c.id);

  const isEditingSuggestion = !isNote && state.editingSuggestion === c.id;
  let suggestionHtml = "";
  if (isEditingSuggestion) {
    const draft = hasSuggestion(c) ? suggestionText(c) : (state.suggestionDrafts.get(c.id) || "");
    const originalText = originalTextForComment(c, opts.sourceLines);
    suggestionHtml = `
      <div class="comment-suggestion">
        <div class="comment-suggestion-label">
          <i data-lucide="lightbulb"></i>
          Suggested change
        </div>
        <textarea class="suggestion-edit" data-edit-suggestion="${idSafe}" autofocus>${escapeHtml(draft)}</textarea>
        <div class="suggestion-warning" data-suggestion-warning-for="${idSafe}" hidden></div>
        <div class="suggestion-preview" data-suggestion-preview-for="${idSafe}">
          ${renderSuggestionDiffTable(originalText, draft, language, s)}
        </div>
        <div class="comment-body-edit-hint">Cmd/Ctrl+Enter to save · Esc to cancel · empty deletes selected lines</div>
      </div>
    `;
  } else if (!isNote && hasSuggestion(c)) {
    suggestionHtml = renderSuggestionDiff(c, language, opts.sourceLines);
  } else {
    suggestionHtml = "";
  }

  const anchorHtml = anchorStatus === "current" ? "" : `
    <div class="anchor-warning ${anchorSafe}">
      <i data-lucide="${anchorStatus === "moved" ? "move-vertical" : "triangle-alert"}"></i>
      ${anchorStatus === "moved" ? "Anchor moved by refresh." : anchorStatus === "missing" ? "Anchor text no longer appears in this file." : "Anchor text appears in multiple places."}
    </div>
  `;

  const repliesHtml = renderReplies(c);

  const lineRefHtml = opts.withLineRef ? `<span class="comment-line-ref">${lineRef}</span>` : "";
  const closeBtnHtml = opts.withLineRef ? "" :
    `<button class="comment-close" data-collapse-comment="${idSafe}" title="Close (Esc)"><i data-lucide="x"></i></button>`;

  const isEditing = state.editingBody === c.id;
  const actionsMenuHtml = isEditing || isEditingSuggestion ? "" : renderCommentActionsMenu(c, idSafe, anchorCurrent);
  const deleteBtnHtml = isEditing || isEditingSuggestion ? "" :
    `<button class="comment-delete-trigger" data-delete-comment="${idSafe}" title="Delete thread" aria-label="Delete thread"><i data-lucide="trash-2"></i></button>`;
  const bodyHtml = isEditing
    ? `
      <textarea class="comment-body-edit" data-edit-body="${idSafe}" autofocus>${escapeHtml(c.body)}</textarea>
      <div class="comment-editor-preview markdown-body" data-markdown-preview-for="${idSafe}">${renderMarkdown(c.body)}</div>
      <div class="comment-body-edit-hint">Cmd/Ctrl+Enter to save · Esc to cancel</div>
    `
    : hasBody ? `<div class="comment-body markdown-body">${renderMarkdown(c.body)}</div>` : "";

  return `
    <div class="comment-card ${type}" data-comment-card="${idSafe}">
      <div class="comment-header">
        ${renderAuthorBadge(author)}
        ${renderMetaChip("type", type, isNote ? "Note" : "Comment")}
        ${renderMetaChip("severity", sev, `Severity: ${humanSeverity(sev)}`)}
        ${renderMetaChip("confidence", confidence, `Confidence: ${humanConfidence(confidence)}`)}
        ${renderMetaChip("category", c.category || "uncategorized", c.category || "uncategorized")}
        ${lineRefHtml}
        <span class="comment-header-spacer"></span>
        ${actionsMenuHtml}
        ${deleteBtnHtml}
        ${closeBtnHtml}
      </div>
      ${anchorHtml}
      ${bodyHtml}
      ${suggestionHtml}
      ${repliesHtml}
      <div class="comment-actions">
        ${renderStatusDropdown(c, idSafe)}
        <div class="spacer"></div>
        <button class="btn" data-add-reply="${idSafe}">
          <i data-lucide="message-square-plus"></i>
          Add reply
        </button>
        ${isNote ? "" : `
        <button class="btn btn-primary" data-send-comment="${idSafe}" title="${escapeHtml(sendBlockReason || "Send this comment to GitHub")}" ${sendBlockReason ? "disabled" : ""}>
          <i data-lucide="send"></i>
          Send this comment
        </button>
        `}
      </div>
    </div>
  `;
}

function renderReplies(c) {
  const replies = Array.isArray(c.replies) ? c.replies : [];
  const idSafe = escapeHtml(c.id);
  const repliesHtml = replies.length === 0 ? "" : `
    <div class="thread-replies">
      ${replies.map((reply) => {
        const author = reply.author || "user";
        const kind = authorKind(author);
        return `
        <div class="thread-reply ${kind}">
          <div class="thread-reply-author">${renderAuthorBadge(author, "reply-author-badge")}</div>
          <div class="thread-reply-body markdown-body">${renderMarkdown(reply.body || "")}</div>
        </div>
      `;
      }).join("")}
    </div>
  `;

  return `
    ${repliesHtml}
    <textarea class="thread-reply-input" data-reply-input="${idSafe}" placeholder="Reply locally for the next terminal /assisted-review iteration..."></textarea>
  `;
}

function renderSuggestionDiff(c, language, sourceLinesArg) {
  const [s] = commentLineRange(c);
  const originalText = originalTextForComment(c, sourceLinesArg);

  return `
    <div class="comment-suggestion">
      <div class="comment-suggestion-label">
        <i data-lucide="lightbulb"></i>
        Suggested change
      </div>
      ${renderSuggestionDiffTable(originalText, suggestionText(c), language, s)}
    </div>
  `;
}

// === Mutation helpers ==============================================

async function persistReview() {
  const { _slug, _key, _stale, ...payload } = state.review;
  await putReview(state.route.slug, state.route.key, payload);
}

async function saveEditedBody(id, newBody) {
  const c = findDiscussionTarget(id);
  if (!c) return;
  if (newBody === c.body) {
    state.editingBody = null;
    renderContent();
    return;
  }
  const original = c.body;
  c.body = newBody;
  try {
    await persistReview();
    state.editingBody = null;
    clearFilePaneCache();
    renderContent();
    showToast(overviewKind(id) ? "Edited overview" : "Edited thread", { kind: "success" });
  } catch (err) {
    c.body = original;
    showError(err, "Save failed");
  }
}

function cancelBodyEdit() {
  state.editingBody = null;
  renderContent();
}

async function beginSuggestionEdit(id) {
  const c = findThread(id);
  if (!c) return;
  if (isNoteThread(c)) return;
  if (c.anchor_status && c.anchor_status !== "current" && c.anchor_status !== "moved") {
    showToast("Refresh or move the anchor before editing suggestions", { kind: "warning" });
    return;
  }
  let source = null;
  try {
    source = await ensureSourceForFile(c.file);
  } catch (err) {
    showError(err, "Could not load source for suggestion");
  }
  if (!hasSuggestion(c) && !state.suggestionDrafts.has(id)) {
    if (source) {
      const [s, e] = commentLineRange(c);
      state.suggestionDrafts.set(id, source.split("\n").slice(s - 1, e).join("\n"));
    } else {
      state.suggestionDrafts.set(id, "");
    }
  }
  state.editingSuggestion = id;
  renderContent();
  requestAnimationFrame(() => {
    const editor = document.querySelector(`[data-edit-suggestion="${id}"]`)?._cm;
    if (editor) {
      editor.focus();
      editor.setCursor(editor.lineCount() - 1);
    } else {
      const ta = document.querySelector(`[data-edit-suggestion="${id}"]`);
      ta?.focus();
      ta?.setSelectionRange(ta.value.length, ta.value.length);
    }
  });
}

async function saveEditedSuggestion(id, rawValue) {
  const c = findThread(id);
  if (!c) return;
  const hadSuggestion = hasSuggestion(c);
  const originalSuggestion = hadSuggestion ? suggestionText(c) : undefined;
  const newSuggestion = normalizeSuggestionText(rawValue);
  const originalSourceText = originalTextForComment(c);
  const isUnchangedDraft = !hadSuggestion && newSuggestion === originalSourceText;

  if (isUnchangedDraft || (hadSuggestion && newSuggestion === originalSuggestion)) {
    state.editingSuggestion = null;
    state.suggestionDrafts.delete(id);
    renderContent();
    return;
  }

  c.suggestion = newSuggestion;
  try {
    await persistReview();
    state.editingSuggestion = null;
    state.suggestionDrafts.delete(id);
    clearFilePaneCache();
    renderContent();
    showToast(
      newSuggestion ? (hadSuggestion ? "Edited suggestion" : "Added suggestion") : "Saved deletion suggestion",
      { kind: "success" },
    );
  } catch (err) {
    if (originalSuggestion !== undefined) c.suggestion = originalSuggestion;
    else delete c.suggestion;
    showError(err, "Save failed");
  }
}

async function deleteSuggestion(id) {
  const c = findThread(id);
  if (!hasSuggestion(c) || isNoteThread(c)) return;
  if (!confirm("Delete this suggestion?")) return;
  const originalSuggestion = suggestionText(c);
  delete c.suggestion;
  try {
    await persistReview();
    clearFilePaneCache();
    renderContent();
    showToast("Deleted suggestion", { kind: "success" });
  } catch (err) {
    c.suggestion = originalSuggestion;
    showError(err, "Delete failed");
  }
}

function cancelSuggestionEdit(id) {
  state.editingSuggestion = null;
  state.suggestionDrafts.delete(id);
  renderContent();
}

function ensureContentDelegation(content) {
  if (!content || content._assistedReviewDelegated) return;
  content._assistedReviewDelegated = true;
  content.addEventListener("click", handleDelegatedContentClick);
}

function handleDelegatedContentClick(event) {
  const content = document.getElementById("content");
  const target = event.target instanceof Element
    ? event.target.closest("[data-comment-id], [data-add-line], [data-show-deletion-hunk], .file-group-header[data-file]")
    : null;
  if (!target || !content?.contains(target)) return;

  const commentId = target.getAttribute("data-comment-id");
  if (commentId) {
    toggleComment(commentId);
    return;
  }

  const addLine = target.getAttribute("data-add-line");
  if (addLine) {
    const line = parseInt(addLine, 10);
    state.newCommentTarget = {
      file: state.route.file,
      line,
      isRange: false,
      endLine: line,
    };
    state.newThreadType = state.threadFilter === "note" ? "note" : "comment";
    resetNewCommentSuggestion();
    renderContent();
    requestAnimationFrame(() => {
      const bodyEl = document.getElementById("new-body");
      if (bodyEl?._cm) bodyEl._cm.focus();
      else bodyEl?.focus();
    });
    return;
  }

  const hunkIndex = Number(target.getAttribute("data-show-deletion-hunk"));
  if (Number.isInteger(hunkIndex)) {
    event.stopPropagation();
    const groupIndex = Number(target.getAttribute("data-show-deletion-group"));
    state.cursorHunk = { file: state.route.file, index: hunkIndex };
    setDiffVisible(true);
    if (Number.isInteger(groupIndex)) {
      scrollDeletionGroupIntoView(groupIndex, hunkIndex);
    } else {
      scrollHunkIntoView(hunkIndex);
    }
    return;
  }

  const file = target.getAttribute("data-file");
  if (file && target.classList.contains("file-group-header")) {
    navigate({ view: "file", slug: state.route.slug, key: state.route.key, file });
  }
}

function initializeEditors(content) {
  const newBodyEl = content.querySelector("#new-body");
  if (newBodyEl) {
    const previewEl = content.querySelector("#new-body-preview");
    if (previewEl) previewEl.innerHTML = renderMarkdown(editorValue(newBodyEl));
    bindCodeEditor(newBodyEl, {
      modeInfo: markdownModeInfo(),
      lineWrapping: true,
      onSave: () => content.querySelector("[data-save-new]")?.click(),
      onCancel: () => {
        state.newCommentTarget = null;
        resetNewCommentSuggestion();
        renderContent();
      },
      onChange: (value) => {
        if (previewEl) previewEl.innerHTML = renderMarkdown(value);
      },
    });
  }

  const newSuggestionEl = content.querySelector("#new-suggestion");
  if (newSuggestionEl) {
    const t = state.newCommentTarget;
    const language = detectLanguage(t.file, state.source?.content);
    const originalText = originalTextForNewComment();
    const previewEl = content.querySelector("#new-suggestion-preview");
    const warningEl = content.querySelector("#new-suggestion-warning");
    updateSuggestionPreview(previewEl, warningEl, originalText, editorValue(newSuggestionEl), language, t.line);
    bindCodeEditor(newSuggestionEl, {
      modeInfo: codeMirrorModeInfo(t.file, language),
      lineWrapping: false,
      indentWithTabs: originalText.includes("\t"),
      onSave: () => content.querySelector("[data-save-new]")?.click(),
      onCancel: () => {
        state.newCommentTarget = null;
        resetNewCommentSuggestion();
        renderContent();
      },
      onChange: (value) => {
        state.newCommentSuggestionDraft = value;
        updateSuggestionPreview(previewEl, warningEl, originalText, value, language, t.line);
      },
    });
  }

  content.querySelectorAll("[data-edit-body]").forEach((el) => {
    const id = el.getAttribute("data-edit-body");
    const previewEl = content.querySelector(`[data-markdown-preview-for="${id}"]`);
    bindCodeEditor(el, {
      modeInfo: markdownModeInfo(),
      lineWrapping: true,
      onSave: () => saveEditedBody(id, editorValue(el)),
      onCancel: cancelBodyEdit,
      onChange: (value) => {
        if (previewEl) previewEl.innerHTML = renderMarkdown(value);
      },
    });
  });

  content.querySelectorAll("[data-edit-suggestion]").forEach((el) => {
    const id = el.getAttribute("data-edit-suggestion");
    const c = findThread(id);
    if (!c) return;
    const sourceContent = state.source?.file === c.file ? state.source.content : state.sourceCache.get(c.file);
    const language = detectLanguage(c.file, sourceContent);
    const [s] = commentLineRange(c);
    const originalText = originalTextForComment(c);
    const previewEl = content.querySelector(`[data-suggestion-preview-for="${id}"]`);
    const warningEl = content.querySelector(`[data-suggestion-warning-for="${id}"]`);
    updateSuggestionPreview(previewEl, warningEl, originalText, editorValue(el), language, s);
    bindCodeEditor(el, {
      modeInfo: codeMirrorModeInfo(c.file, language),
      lineWrapping: false,
      indentWithTabs: originalText.includes("\t"),
      onSave: () => saveEditedSuggestion(id, editorValue(el)),
      onCancel: () => cancelSuggestionEdit(id),
      onChange: (value) => updateSuggestionPreview(previewEl, warningEl, originalText, value, language, s),
    });
  });
}

// === Content event handlers ========================================

function attachContentHandlers() {
  const content = document.getElementById("content");
  ensureContentDelegation(content);
  initializeEditors(content);

  // New-comment form handlers
  content.querySelectorAll("[data-cancel-new]").forEach((el) => {
    el.addEventListener("click", () => {
      state.newCommentTarget = null;
      resetNewCommentSuggestion();
      renderContent();
    });
  });
  content.querySelectorAll("#new-range-toggle").forEach((el) => {
    el.addEventListener("change", (e) => {
      state.newCommentTarget.isRange = e.target.checked;
      if (!state.newCommentTarget.isRange) {
        state.newCommentTarget.endLine = state.newCommentTarget.line;
      }
      state.newCommentSuggestionDraft = "";
      renderContent();
    });
  });
  content.querySelectorAll("[data-new-thread-type]").forEach((el) => {
    el.addEventListener("click", () => {
      const nextType = el.getAttribute("data-new-thread-type");
      if (!["comment", "note"].includes(nextType) || state.newThreadType === nextType) return;
      state.newThreadType = nextType;
      if (nextType === "note") resetNewCommentSuggestion();
      renderContent();
    });
  });
  content.querySelectorAll("[data-expand-new-suggestion]").forEach((el) => {
    el.addEventListener("click", () => {
      state.newCommentSuggestionExpanded = true;
      state.newCommentSuggestionDraft = originalTextForNewComment();
      renderContent();
      requestAnimationFrame(() => {
        const suggestionEl = document.getElementById("new-suggestion");
        if (suggestionEl?._cm) suggestionEl._cm.focus();
        else suggestionEl?.focus();
      });
    });
  });
  content.querySelectorAll("[data-collapse-new-suggestion]").forEach((el) => {
    el.addEventListener("click", () => {
      state.newCommentSuggestionExpanded = false;
      state.newCommentSuggestionDraft = "";
      renderContent();
    });
  });
  content.querySelectorAll("[data-save-new]").forEach((el) => {
    el.addEventListener("click", async () => {
      const t = state.newCommentTarget;
      const bodyEl = document.getElementById("new-body");
      const suggestionEl = document.getElementById("new-suggestion");
      const body = editorValue(bodyEl).trim();
      const isNote = state.newThreadType === "note";
      const category = document.getElementById("new-category").value.trim() || (isNote ? "context" : "correctness");
      const severity = document.getElementById("new-severity").value;
      const confidence = document.getElementById("new-confidence").value;
      const suggestion = !isNote && state.newCommentSuggestionExpanded
        ? normalizeSuggestionText(editorValue(suggestionEl))
        : "";
      const endLineEl = document.getElementById("new-end-line");
      const endLine = t.isRange && endLineEl ? parseInt(endLineEl.value, 10) : t.line;
      const originalSuggestion = sourceTextForRange(t.file, t.line, endLine);

      if (!body) {
        showToast("Thread body is required", { kind: "warning" });
        return;
      }
      if (t.isRange && endLine < t.line) {
        showToast("End line must be ≥ start line", { kind: "warning" });
        return;
      }

      const newComment = {
        id: nextCommentId(),
        type: state.newThreadType,
        author: "user",
        file: t.file,
        line: endLine,
        severity,
        category,
        confidence,
        body,
        status: "open",
        anchor_text: originalSuggestion,
        anchor_status: "current",
        replies: [],
      };
      if (t.isRange && endLine !== t.line) newComment.start_line = t.line;
      if (!isNote && state.newCommentSuggestionExpanded && suggestion !== originalSuggestion) {
        newComment.suggestion = suggestion;
      }

      reviewThreads().push(newComment);
      try {
        await persistReview();
        state.newCommentTarget = null;
        resetNewCommentSuggestion();
        state.expandedComments.add(newComment.id);
        clearFilePaneCache();
        renderTree();
        renderContent();
        showToast(`Added ${isNote ? "note" : "comment"}`, { kind: "success" });
      } catch (err) {
        showError(err, "Save failed");
        // Roll back optimistic update
        state.review.review.threads = reviewThreads().filter((c) => c.id !== newComment.id);
      }
    });
  });

  // Header actions menu → enter comment-body edit mode
  content.querySelectorAll("[data-edit-target]").forEach((el) => {
    el.addEventListener("click", () => {
      state.editingBody = el.getAttribute("data-edit-target");
      renderContent();
      requestAnimationFrame(() => {
        const ta = document.querySelector(`[data-edit-body="${state.editingBody}"]`);
        if (ta?._cm) {
          ta._cm.focus();
          ta._cm.setCursor(ta._cm.lineCount() - 1);
        } else if (ta) {
          ta.focus();
          ta.setSelectionRange(ta.value.length, ta.value.length);
        }
      });
    });
  });

  // Edit-body keyboard handlers
  content.querySelectorAll("[data-edit-body]").forEach((el) => {
    el.addEventListener("keydown", async (e) => {
      const id = el.getAttribute("data-edit-body");
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault();
        await saveEditedBody(id, editorValue(el));
      } else if (e.key === "Escape") {
        // Stop propagation so the global Esc handler doesn't *also* collapse
        // the surrounding comment. Esc here only exits edit mode.
        e.preventDefault();
        e.stopPropagation();
        suppressGlobalEscapeCollapse();
        cancelBodyEdit();
      }
    });
  });

  // Pencil button on the suggestion label (or "Add suggested change" button
   // when no suggestion exists) → swap diff for an editable textarea.
  content.querySelectorAll("[data-edit-suggestion-target]").forEach((el) => {
    el.addEventListener("click", async (e) => {
      e.stopPropagation();
      await beginSuggestionEdit(el.getAttribute("data-edit-suggestion-target"));
    });
  });

  // Edit-suggestion keyboard handlers (Cmd/Ctrl+Enter saves, Esc cancels).
  content.querySelectorAll("[data-edit-suggestion]").forEach((el) => {
    el.addEventListener("keydown", async (e) => {
      const id = el.getAttribute("data-edit-suggestion");
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault();
        await saveEditedSuggestion(id, editorValue(el));
      } else if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        suppressGlobalEscapeCollapse();
        cancelSuggestionEdit(id);
      }
    });
  });

  content.querySelectorAll("[data-collapse-comment]").forEach((el) => {
    el.addEventListener("click", (e) => {
      e.stopPropagation();
      state.expandedComments.delete(el.getAttribute("data-collapse-comment"));
      renderContent();
    });
  });

  content.querySelectorAll("[data-set-status]").forEach((el) => {
    el.addEventListener("click", async (e) => {
      e.stopPropagation();
      const id = el.getAttribute("data-set-status");
      const status = el.getAttribute("data-status-value");
      el.closest("details.status-menu")?.removeAttribute("open");
      await setStatus(id, status);
    });
  });

  content.querySelectorAll("[data-delete-suggestion]").forEach((el) => {
    el.addEventListener("click", async () => {
      await deleteSuggestion(el.getAttribute("data-delete-suggestion"));
    });
  });

  content.querySelectorAll("[data-delete-comment]").forEach((el) => {
    el.addEventListener("click", async (e) => {
      e.stopPropagation();
      const id = el.getAttribute("data-delete-comment");
      if (!confirm("Delete this thread?")) return;
      const originalThreads = [...reviewThreads()];
      state.review.review.threads = reviewThreads().filter((c) => c.id !== id);
      try {
        await persistReview();
        clearFilePaneCache();
        renderTree();
        renderContent();
        showToast("Deleted thread", { kind: "success" });
      } catch (err) {
        state.review.review.threads = originalThreads;
        showError(err, "Delete failed");
      }
    });
  });

  content.querySelectorAll("[data-add-reply]").forEach((el) => {
    el.addEventListener("click", async () => {
      const id = el.getAttribute("data-add-reply");
      const ta = content.querySelector(`[data-reply-input="${id}"]`);
      const c = findDiscussionTarget(id);
      if (!ta || !c) return;
      const body = ta.value.trim();
      if (!body) {
        showToast("Reply body is required", { kind: "warning" });
        return;
      }
      if (!Array.isArray(c.replies)) c.replies = [];
      c.replies.push({ author: "user", body });
      try {
        await persistReview();
        clearFilePaneCache();
        renderContent();
        showToast("Reply added", { kind: "success" });
      } catch (err) {
        showError(err, "Save failed");
      }
    });
  });

  content.querySelectorAll("[data-send-comment]").forEach((el) => {
    el.addEventListener("click", async () => {
      const id = el.getAttribute("data-send-comment");
      const blockReason = commentSendBlockReason(findThread(id));
      if (blockReason) {
        showToast("Cannot send comment", { kind: "warning", detail: blockReason });
        return;
      }
      if (!confirm("Send this comment to GitHub?")) return;
      try {
        await submitReview(state.route.slug, state.route.key, { mode: "comment", commentId: id });
        // Reload the review (server removed the thread).
        state.review = null;
        await loadRoute(state.route);
        showToast("Sent comment", { kind: "success" });
      } catch (err) {
        showError(err, "Submission failed");
      }
    });
  });
}

async function toggleComment(id) {
  const willExpand = !state.expandedComments.has(id);
  if (state.expandedComments.has(id)) {
    state.expandedComments.delete(id);
  } else {
    state.expandedComments.add(id);
    state.cursorCommentId = id;
  }
  state.cursorHunk = null;
  clearHunkFocusRows();
  syncExpandedCommentRows();
  renderContextbar();
  if (willExpand) scrollCommentIntoView(id);
}

const NAV_SCROLL_TOP_OFFSET = 16;
const FOCUS_LINE_OFFSET = 120;
const COMMENT_CONTEXT_LINE_MAX = 10;

function scrollCommentIntoView(id) {
  requestAnimationFrame(() => {
    const thread = findThread(id);
    const card = document.querySelector(`[data-comment-card="${id}"]`);
    const content = document.getElementById("content");
    if (!card || !content) return;
    let target = card;
    if (thread) {
      const [startLine, endLine] = commentLineRange(thread);
      const targetLine = Math.max(startLine, endLine - COMMENT_CONTEXT_LINE_MAX + 1);
      target = document.querySelector(`[data-source-line="${targetLine}"]`) || card;
    }
    scrollElementToContentTop(target, content, NAV_SCROLL_TOP_OFFSET);
  });
}

function scrollHunkIntoView(index) {
  requestAnimationFrame(() => {
    const row = firstVisibleElement(`[data-hunk-index="${index}"]`);
    const content = document.getElementById("content");
    if (!row && !state.diffVisible) {
      state.diffVisible = true;
      localStorage.setItem("assistedReviewDiffVisible", "1");
      applyDiffVisibility(true);
      scrollHunkIntoView(index);
      return;
    }
    if (!row || !content) return;
    scrollElementToContentTop(row, content, NAV_SCROLL_TOP_OFFSET);
    focusHunkRows(index);
  });
}

function scrollDeletionGroupIntoView(groupIndex, fallbackHunkIndex) {
  requestAnimationFrame(() => {
    const content = document.getElementById("content");
    const row = firstVisibleElement(`[data-deletion-group="${groupIndex}"]`);
    if (!row || !content) {
      scrollHunkIntoView(fallbackHunkIndex);
      return;
    }
    scrollElementToContentTop(row, content, NAV_SCROLL_TOP_OFFSET);
    focusHunkRows(fallbackHunkIndex);
  });
}

function scrollElementToContentTop(element, content, offset) {
  const top =
    element.getBoundingClientRect().top -
    content.getBoundingClientRect().top +
    content.scrollTop -
    offset;
  content.scrollTo({ top, behavior: "smooth" });
}

function firstVisibleElement(selector) {
  return Array.from(document.querySelectorAll(selector)).find((el) => {
    const style = window.getComputedStyle(el);
    return style.display !== "none" && style.visibility !== "hidden";
  }) || null;
}

function setOnlyExpandedComment(id) {
  state.expandedComments.clear();
  if (id) state.expandedComments.add(id);
  syncExpandedCommentRows();
}

function syncExpandedCommentRows(root = document) {
  root.querySelectorAll("[data-comment-row-id]").forEach((row) => {
    row.hidden = !state.expandedComments.has(row.getAttribute("data-comment-row-id"));
  });
}

function focusHunkRows(index) {
  clearHunkFocusRows();
  document.querySelectorAll(`[data-hunk-member="${index}"]`).forEach((el) => {
    el.classList.add("nav-focus", "nav-focus-hunk");
    focusedHunkElements.add(el);
  });
}

function clearHunkFocusRows() {
  focusedHunkElements.forEach((el) => {
    el.classList.remove("nav-focus", "nav-focus-hunk");
  });
  focusedHunkElements = new Set();
}

function syncFocusedHunkRows() {
  clearHunkFocusRows();
  if (state.cursorHunk?.file === state.route.file) focusHunkRows(state.cursorHunk.index);
}

function focusedSourceLine() {
  const content = document.getElementById("content");
  if (!content) return null;
  const focusY = content.getBoundingClientRect().top + FOCUS_LINE_OFFSET;
  let best = null;
  let bestDistance = Infinity;
  document.querySelectorAll("[data-source-line]").forEach((row) => {
    const rect = row.getBoundingClientRect();
    const distance = Math.abs(rect.top - focusY);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = Number(row.getAttribute("data-source-line"));
    }
  });
  return Number.isInteger(best) ? best : null;
}

function restoreFocusedSourceLine(line) {
  if (!Number.isInteger(line)) return;
  requestAnimationFrame(() => {
    const content = document.getElementById("content");
    const row = document.querySelector(`[data-source-line="${line}"]`);
    if (!content || !row) return;
    const top =
      row.getBoundingClientRect().top -
      content.getBoundingClientRect().top +
      content.scrollTop -
      FOCUS_LINE_OFFSET;
    content.scrollTo({ top });
  });
}

async function setStatus(commentId, status) {
  const c = findThread(commentId);
  if (!c) return;
  if (!STATUS_OPTIONS.some((option) => option.value === status) || c.status === status) {
    renderContent();
    return;
  }
  const original = c.status;
  c.status = status;
  try {
    await persistReview();
    clearFilePaneCache();
    renderContent();
  } catch (err) {
    c.status = original;
    showError(err, "Save failed");
  }
}

function setDiffVisible(visible) {
  const next = Boolean(visible);
  if (state.diffVisible === next) return;
  const focusLine = focusedSourceLine();
  state.diffVisible = next;
  localStorage.setItem("assistedReviewDiffVisible", next ? "1" : "0");
  applyDiffVisibility(next);
  restoreFocusedSourceLine(focusLine);
}

function toggleDiffVisible() {
  setDiffVisible(!state.diffVisible);
}

function applyDiffVisibility(visible) {
  document.querySelectorAll(".code-table.full-source-table").forEach((table) => {
    table.classList.toggle("diff-overlay-on", visible);
    table.classList.toggle("diff-overlay-off", !visible);
  });

  document.querySelectorAll("[data-diff-visible]").forEach((button) => {
    const buttonVisible = button.getAttribute("data-diff-visible") === "1";
    const active = buttonVisible === visible;
    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
}

function setNavTarget(target) {
  if (!["comments", "hunks"].includes(target) || state.navTarget === target) return;
  state.navTarget = target;
  if (target === "comments") {
    state.cursorHunk = null;
    clearHunkFocusRows();
  }
  localStorage.setItem("assistedReviewNavTarget", target);
  renderContextbar();
}

function toggleNavTarget() {
  setNavTarget(state.navTarget === "comments" ? "hunks" : "comments");
}

function setThreadFilter(filter) {
  if (!["all", "comment", "note"].includes(filter) || state.threadFilter === filter) return;
  state.threadFilter = filter;
  localStorage.setItem("assistedReviewThreadFilter", filter);
  clearFilePaneCache();
  renderContent();
}

async function applyBaseRef() {
  if (!state.review) return;
  const base = String(state.baseDraft || "").trim();
  if (!base) {
    showToast("Base ref is required", { kind: "warning" });
    return;
  }
  try {
    const payload = await fetchDiffSummary(state.route.slug, state.route.key, { base });
    state.diffSummary = payload;
    state.diffError = null;
    state.diffFileCache.clear();
    clearFilePaneCache();
    state.baseDraft = payload.base_ref || base;
    state.review.target = state.review.target || {};
    state.review.target.base_ref = state.baseDraft;
    await persistReview();
    if (state.route.view === "file") {
      await ensureDiffForFile(state.route.file);
    }
    renderContent();
    showToast("Updated diff base", { kind: "success", detail: state.baseDraft });
  } catch (err) {
    showError(err, "Base ref failed");
  }
}

// === Topbar actions ================================================

document.getElementById("btn-home").addEventListener("click", () => {
  navigate({ view: "inbox" });
});

document.addEventListener("pointerdown", (e) => {
  const target = e.target instanceof Element ? e.target : null;
  closeOpenDisclosureMenus(target);
});

document.getElementById("btn-refresh-review").addEventListener("click", async () => {
  if (!state.review) {
    showToast("Open a review to refresh it", { kind: "warning" });
    return;
  }
  const needsRefresh = Boolean(state.refreshStatus?.needs_refresh ?? state.review._stale);
  if (!needsRefresh) {
    showToast("No filesystem changes detected", { kind: "info" });
    return;
  }
  try {
    const res = await refreshReview(state.route.slug, state.route.key);
    state.review = null;
    state.refreshStatus = null;
    state.source = null;
    state.fullTree = null;
    state.diffSummary = null;
    state.diffError = null;
    state.sourceCache.clear();
    state.diffFileCache.clear();
    clearFilePaneCache();
    await loadRoute(state.route);
    await updateRefreshStatus();
    const counts = res.counts || {};
    showToast("Refreshed review", {
      kind: "success",
      detail: `${counts.moved || 0} moved · ${counts.missing || 0} missing · ${counts.ambiguous || 0} ambiguous`,
    });
  } catch (err) {
    showError(err, "Refresh failed");
  }
});

document.getElementById("btn-send-review").addEventListener("click", async () => {
  const blockReason = reviewSendBlockReason();
  if (blockReason) {
    showToast("Cannot submit review", { kind: "warning", detail: blockReason });
    return;
  }
  const { sendableComments, notes } = submissionSummary();
  if (!confirm(`Send ${sendableComments} open or acknowledged comment${sendableComments === 1 ? "" : "s"} to GitHub? ${notes} note${notes === 1 ? "" : "s"} will stay local.`)) return;
  try {
    const res = await submitReview(state.route.slug, state.route.key, { mode: "all" });
    showToast("Sent review", { kind: "success", detail: res.url || "" });
    if (res.archived) {
      navigate({ view: "inbox" });
    } else {
      state.review = null;
      await loadRoute(state.route);
    }
  } catch (err) {
    showError(err, "Submission failed");
  }
});

// === Keyboard navigation ==========================================

function isTypingInInput() {
  const a = document.activeElement;
  if (!a) return false;
  return a.tagName === "INPUT" || a.tagName === "TEXTAREA" || a.isContentEditable;
}

function navigableComments() {
  if (!state.review) return [];
  const grouped = {};
  visibleReviewThreads().forEach((c) => {
    if (!grouped[c.file]) grouped[c.file] = [];
    grouped[c.file].push(c);
  });
  return Object.entries(grouped)
    .sort(([a], [b]) => a.localeCompare(b))
    .flatMap(([, group]) =>
      group.sort((a, b) => commentLineRange(a)[0] - commentLineRange(b)[0]),
    );
}

function navigableHunks() {
  if (!state.diffSummary) return [];
  return diffFiles()
    .filter((file) => (file.hunks || []).length > 0)
    .sort((a, b) => a.file.localeCompare(b.file))
    .flatMap((file) =>
      (file.hunks || []).map((hunk, index) => ({
        ...hunk,
        file: file.file,
        index,
      })),
    );
}

async function navigateByTarget(direction) {
  if (state.navTarget === "hunks") {
    await navigateToHunk(direction);
  } else {
    await navigateToComment(direction);
  }
}

async function navigateToComment(direction) {
  if (state.route.view === "inbox") return;
  const comments = navigableComments();
  if (comments.length === 0) return;

  const currentIdx = state.cursorCommentId
    ? comments.findIndex((c) => c.id === state.cursorCommentId)
    : -1;
  const nextIdx = fileScopedNavIndex(comments, currentIdx, direction);
  const target = comments[nextIdx];
  state.cursorCommentId = target.id;
  state.cursorHunk = null;
  clearHunkFocusRows();

  if (state.route.view !== "file" || state.route.file !== target.file) {
    await navigate(
      { view: "file", slug: state.route.slug, key: state.route.key, file: target.file },
      false,
      { preserveNavCursor: true },
    );
  }
  setOnlyExpandedComment(target.id);
  renderContextbar();
  scrollCommentIntoView(target.id);
}

async function navigateToHunk(direction) {
  if (state.route.view === "inbox") return;
  const hunks = navigableHunks();
  if (hunks.length === 0) return;

  const currentIdx = state.cursorHunk
    ? hunks.findIndex((h) => h.file === state.cursorHunk.file && h.index === state.cursorHunk.index)
    : -1;
  const nextIdx = fileScopedNavIndex(hunks, currentIdx, direction);
  const target = hunks[nextIdx];
  state.cursorHunk = { file: target.file, index: target.index };

  if (state.route.view !== "file" || state.route.file !== target.file) {
    await navigate(
      { view: "file", slug: state.route.slug, key: state.route.key, file: target.file },
      false,
      { preserveNavCursor: true },
    );
  }
  renderContextbar();
  scrollHunkIntoView(target.index);
}

function fileScopedNavIndex(items, currentIdx, direction) {
  if (currentIdx !== -1) {
    return (currentIdx + direction + items.length) % items.length;
  }

  const currentFile = state.route.view === "file" ? state.route.file : null;
  if (!currentFile) return direction > 0 ? 0 : items.length - 1;

  const firstInFile = items.findIndex((item) => item.file === currentFile);
  if (firstInFile !== -1) {
    if (direction > 0) return firstInFile;
    for (let i = items.length - 1; i >= 0; i -= 1) {
      if (items[i].file === currentFile) return i;
    }
  }

  if (direction > 0) {
    const nextFileIdx = items.findIndex((item) => item.file.localeCompare(currentFile) > 0);
    return nextFileIdx === -1 ? 0 : nextFileIdx;
  }

  for (let i = items.length - 1; i >= 0; i -= 1) {
    if (items[i].file.localeCompare(currentFile) < 0) return i;
  }
  return items.length - 1;
}

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && shouldSuppressGlobalEscapeCollapse()) {
    e.preventDefault();
    e.stopPropagation();
    return;
  }

  if (isTypingInInput()) {
    if (e.key === "Escape") {
      document.activeElement.blur();
      e.preventDefault();
      e.stopPropagation();
    }
    return;
  }

  if (e.key === "Tab" && !e.shiftKey) {
    e.preventDefault();
    navigateByTarget(+1);
  } else if (e.key === "Tab" && e.shiftKey) {
    e.preventDefault();
    navigateByTarget(-1);
  } else if (e.key === "j") {
    e.preventDefault();
    navigateByTarget(+1);
  } else if (e.key === "k") {
    e.preventDefault();
    navigateByTarget(-1);
  } else if (e.key === "d") {
    e.preventDefault();
    toggleDiffVisible();
  } else if (e.key === "c") {
    e.preventDefault();
    setNavTarget("comments");
  } else if (e.key === "h") {
    e.preventDefault();
    setNavTarget("hunks");
  } else if (e.key === "n") {
    e.preventDefault();
    toggleNavTarget();
  } else if (e.key === "Escape") {
    if (state.newCommentTarget) {
      state.newCommentTarget = null;
      resetNewCommentSuggestion();
      renderContent();
    } else if (state.expandedComments.size > 0) {
      state.expandedComments.clear();
      renderContent();
    }
  } else if (e.key === "?") {
    showToast("Keys: Tab/S-Tab or j/k navigate selected target · d diff · c comments · h hunks · n switch target · Esc close");
  }
});

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "hidden") {
    updateRefreshStatus();
  }
});

window.addEventListener("focus", () => {
  updateRefreshStatus();
});

// === Boot ==========================================================

const initialRoute = parseRoute(window.location.pathname);
window.history.replaceState(initialRoute, "");

// Debug params survive the loadRoute clear because they're applied after.
const debugParams = new URLSearchParams(window.location.search);
loadRoute(initialRoute).then(() => {
  let needsRender = false;
  if (debugParams.get("expand")) {
    debugParams.get("expand").split(",").forEach((id) => state.expandedComments.add(id));
    needsRender = true;
  }
  if (debugParams.get("add") && initialRoute.view === "file") {
    const line = parseInt(debugParams.get("add"), 10);
    state.newCommentTarget = { file: initialRoute.file, line, isRange: false, endLine: line };
    needsRender = true;
  }
  if (debugParams.get("edit")) {
    state.editingBody = debugParams.get("edit");
    state.expandedComments.add(debugParams.get("edit"));
    needsRender = true;
  }
  if (needsRender) renderContent();
});
