// Vanilla JS — no framework, no build step. Talks to the local Python
// daemon via fetch. Path-based routing (HTML5 history API):
//
//   /                                     → inbox
//   /r/<slug>/<key>                       → per-review (overview + comments)
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
  // ui
  inboxFilter: "needs_triage",        // 'needs_triage' | 'iterating' | 'done' | 'stale'
  showStale: false,
  expandedComments: new Set(),
  cursorCommentId: null,              // last navigated/clicked comment — Tab/S-Tab anchor
  treeFilter: { query: "", showAll: false },
  collapsedFolders: new Set(),        // folder paths the user has collapsed in the file tree
  newCommentTarget: null,             // { file, line, isRange, endLine } or null
  editingBody: null,                  // commentId currently being edited inline
  editingSuggestion: null,            // commentId currently editing suggestion inline
  suggestionDrafts: new Map(),         // commentId -> original source replacement text
  error: null,
};

// === Helpers =======================================================

function shortSha(sha) {
  return (sha || "").slice(0, 7);
}

function commentLineRange(c) {
  if (c.start_line && c.line && c.start_line !== c.line) {
    return [c.start_line, c.line];
  }
  return [c.line, c.line];
}

function severityOrder(sev) {
  return { critical: 0, high: 1, medium: 2, low: 3, info: 4 }[sev] ?? 5;
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
    return sanitizeRenderedMarkdown(window.marked.parse(src, { breaks: false, gfm: true }));
  }
  return `<pre class="comment-body-fallback">${escapeHtml(src)}</pre>`;
}

function sanitizeRenderedMarkdown(html) {
  const template = document.createElement("template");
  template.innerHTML = html;
  template.content.querySelectorAll("script, style, iframe, object, embed, link, meta, base").forEach((el) => {
    el.remove();
  });
  template.content.querySelectorAll("*").forEach((el) => {
    Array.from(el.attributes).forEach((attr) => {
      const name = attr.name.toLowerCase();
      const value = attr.value.trim().toLowerCase();
      if (name.startsWith("on") || value.startsWith("javascript:")) {
        el.removeAttribute(attr.name);
      }
    });
  });
  return template.innerHTML;
}

function showToast(message) {
  const el = document.getElementById("toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => el.classList.remove("show"), 2400);
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
  if (!window.hljs) return escapeHtml(line) || "&nbsp;";
  try {
    const result = language
      ? window.hljs.highlight(safeLine, { language, ignoreIllegals: true })
      : window.hljs.highlightAuto(safeLine);
    return result.value || "&nbsp;";
  } catch {
    return escapeHtml(line) || "&nbsp;";
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
  if (state.source?.file === filePath) return state.source.content;
  if (state.sourceCache.has(filePath)) return state.sourceCache.get(filePath);
  const content = await fetchSource(state.route.slug, state.route.key, filePath);
  state.sourceCache.set(filePath, content);
  return content;
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

function indentationWarning(originalText, suggestedText) {
  const suggested = normalizeSuggestionText(suggestedText);
  if (!/\S/.test(suggested)) return "";
  const originalLines = String(originalText ?? "").split("\n");
  const suggestedLines = suggested.split("\n");
  let changed = 0;
  const pairedCount = Math.min(originalLines.length, suggestedLines.length);
  for (let i = 0; i < pairedCount; i += 1) {
    if (!/\S/.test(originalLines[i]) || !/\S/.test(suggestedLines[i])) continue;
    if (leadingWhitespace(originalLines[i]) !== leadingWhitespace(suggestedLines[i])) {
      changed += 1;
    }
  }
  if (changed === 0) return "";
  if (originalLines.length === 1 && suggestedLines.length === 1) {
    return "Leading whitespace differs from the original line. GitHub will apply that indentation exactly.";
  }
  return changed === 1
    ? "1 paired line changes its leading whitespace. GitHub will apply indentation exactly."
    : `${changed} paired lines change their leading whitespace. GitHub will apply indentation exactly.`;
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
      "Esc": () => opts.onCancel?.(),
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

function navigate(route, replace = false) {
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

async function fetchTree(slug, key) {
  const r = await fetch(`/api/tree/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`);
  if (!r.ok) throw new Error(`tree load failed: ${r.status}`);
  return r.json();
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
  if (!r.ok) throw new Error(`save failed: ${r.status}`);
  return r.json();
}

async function deleteReview(slug, key) {
  const r = await fetch(`/api/review/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "DELETE",
  });
  if (!r.ok) throw new Error(`delete failed: ${r.status}`);
  return r.json();
}

async function submitReview(slug, key, body) {
  const r = await fetch(`/api/submit/${encodeURIComponent(slug)}/${encodeURIComponent(key)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(payload.error || `submit failed: ${r.status}`);
  return payload;
}

// === Route loader ==================================================

// File-tree collapsed-folder state is per-review and persisted in localStorage
// so the user's tree shape survives reloads. Key includes slug + key (the
// same identifiers used in the route) so unrelated reviews don't share state.
function collapsedFoldersKey(slug, key) {
  return `code-review:collapsed-folders:${slug}:${key}`;
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

async function loadRoute(route) {
  state.route = route;
  state.error = null;
  state.expandedComments.clear();
  state.newCommentTarget = null;
  state.editingBody = null;
  state.editingSuggestion = null;
  state.suggestionDrafts.clear();

  try {
    if (route.view === "inbox") {
      state.review = null;
      state.source = null;
      state.fullTree = null;
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
        state.sourceCache.clear();
        state.fullTree = null;          // changed review → invalidate tree cache
        state.collapsedFolders = loadCollapsedFolders(route.slug, route.key);
      }
      if (route.view === "file") {
        const content = await fetchSource(route.slug, route.key, route.file);
        state.source = { file: route.file, content };
        state.sourceCache.set(route.file, content);
      } else {
        state.source = null;
      }
    }
  } catch (err) {
    state.error = String(err.message || err);
  }

  document.body.classList.toggle("inbox-mode", state.route.view === "inbox");
  renderTopbar();
  renderTree();
  renderContent();
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
  const saveBtn = document.getElementById("btn-save-feedback");
  const sendBtn = document.getElementById("btn-send-review");
  const navWrap = document.getElementById("topbar-nav");
  const navCounter = document.getElementById("topbar-nav-counter");

  if (state.route.view === "inbox" || !state.review) {
    repoEl.textContent = "code-review";
    branchEl.textContent = "";
    commitEl.textContent = "";
    prEl.textContent = "";
    staleEl.hidden = true;
    sep1.hidden = sep2.hidden = sep3.hidden = true;
    saveBtn.hidden = true;
    sendBtn.hidden = true;
    navWrap.hidden = true;
    return;
  }

  const t = state.review.target || {};
  repoEl.textContent = t.repo_root ? t.repo_root.split("/").pop() : state.route.slug;
  branchEl.textContent = t.branch || "—";
  commitEl.textContent = shortSha(t.commit);
  prEl.textContent = "";
  if (t.pr_number && t.owner && t.repo) {
    // DOM-construct the link instead of innerHTML — pr_number/owner/repo
    // come straight from a YAML on disk that nothing validates at read
    // time, so an unescaped template here is an XSS sink.
    const a = document.createElement("a");
    a.href = `https://github.com/${encodeURIComponent(t.owner)}/${encodeURIComponent(t.repo)}/pull/${encodeURIComponent(t.pr_number)}`;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    a.textContent = `PR #${t.pr_number}`;
    a.addEventListener("click", (e) => e.stopPropagation());
    prEl.appendChild(a);
    sendBtn.disabled = false;
    sendBtn.title = "";
  } else if (t.pr_number) {
    // Have a PR number but no owner/repo — older YAMLs predate the schema
    // bump. Show the number as text so submit still works (the daemon can
    // resolve owner/repo at submit time), but no clickable link.
    prEl.textContent = `PR #${t.pr_number}`;
    sendBtn.disabled = false;
    sendBtn.title = "";
  } else {
    prEl.textContent = "scratch · no PR";
    sendBtn.disabled = true;
    sendBtn.title = "Set target.pr_number to enable submitting";
  }
  sep1.hidden = sep2.hidden = sep3.hidden = false;

  if (state.review._stale) {
    staleEl.textContent = "stale";
    staleEl.className = "topbar-stale";
    staleEl.hidden = false;
    staleEl.title = "HEAD has moved past target.commit — line numbers may not match current files";
  } else {
    staleEl.hidden = true;
  }

  saveBtn.hidden = false;
  sendBtn.hidden = false;

  const navComments = navigableComments();
  if (navComments.length === 0) {
    navWrap.hidden = true;
  } else {
    navWrap.hidden = false;
    const cursorIdx = state.cursorCommentId
      ? navComments.findIndex((c) => c.id === state.cursorCommentId)
      : -1;
    navCounter.textContent = cursorIdx === -1
      ? `${navComments.length}`
      : `${cursorIdx + 1} / ${navComments.length}`;
  }
}

// === File tree =====================================================

function renderTree() {
  const root = document.getElementById("file-tree");

  if (state.route.view === "inbox" || !state.review) {
    root.hidden = true;
    return;
  }

  root.hidden = false;
  const total = (state.review.review?.comments || []).length;
  const isReviewRoot = state.route.view === "review";

  const counts = filesWithCommentCounts();
  const filterQuery = state.treeFilter.query.toLowerCase().trim();

  // Source set: by default just commented files; with showAll, the full repo
  // (fetched lazily on toggle and cached on state).
  const allPaths = state.treeFilter.showAll && state.fullTree
    ? state.fullTree.files.slice()
    : Object.keys(counts);

  const filteredPaths = filterQuery
    ? allPaths.filter((p) => p.toLowerCase().includes(filterQuery))
    : allPaths;

  const tree = buildTreeFromFiles(filteredPaths, counts);

  const filterHtml = `
    <div class="tree-filter">
      <input type="text" id="tree-filter-query" placeholder="Filter files…" value="${escapeHtml(state.treeFilter.query)}" />
      <label class="tree-filter-toggle">
        <input type="checkbox" id="tree-filter-show-all" ${state.treeFilter.showAll ? "checked" : ""} />
        Show all repo files
      </label>
    </div>
  `;

  const treeHtml = filteredPaths.length === 0
    ? state.treeFilter.showAll && !state.fullTree
      ? `<div class="tree-empty">Loading full repo tree…</div>`
      : `<div class="tree-empty">No files match.</div>`
    : `<ul class="tree-node">${tree.map((n) => renderTreeNode(n)).join("")}</ul>`;

  root.innerHTML = `
    ${filterHtml}
    <div class="tree-overview">
      <div class="tree-item overview ${isReviewRoot ? "active" : ""}" data-route="review">
        <i data-lucide="layout-list"></i>
        <span>Overview</span>
        <span class="comment-pip">${total}</span>
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
  (state.review.review?.comments || []).forEach((c) => {
    counts[c.file] = (counts[c.file] || 0) + 1;
  });
  return counts;
}

function buildTreeFromFiles(paths, commentCounts = {}) {
  const root = {};
  paths.forEach((path) => {
    const segs = path.split("/");
    let node = root;
    segs.forEach((seg, i) => {
      const isLeaf = i === segs.length - 1;
      if (isLeaf) {
        node[seg] = { __leaf: true, path, count: commentCounts[path] || 0 };
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
        return { type: "file", name, path: v.path, count: v.count };
      }
      const dirPath = prefix ? `${prefix}/${name}` : name;
      const children = treeObjectToList(v, dirPath);
      // Aggregate descendant comment counts so a collapsed folder can still
      // show users "5 comments are hiding in here" via its pip.
      const dirCount = children.reduce(
        (sum, c) => sum + (c.type === "file" ? c.count : c.dirCount),
        0,
      );
      return { type: "dir", name, path: dirPath, children, dirCount };
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
    const childrenHtml = collapsed
      ? ""
      : `<ul class="tree-node tree-children">${node.children.map((c) => renderTreeNode(c)).join("")}</ul>`;
    return `
      <li>
        <div class="tree-item dir" data-folder="${escapeHtml(node.path)}" title="${escapeHtml(node.path)}">
          <i data-lucide="${chevronIcon}" class="tree-chevron"></i>
          <i data-lucide="${folderIcon}"></i>
          <span class="tree-item-name">${escapeHtml(node.name)}</span>
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

  const showAllToggle = root.querySelector("#tree-filter-show-all");
  if (showAllToggle) {
    showAllToggle.addEventListener("change", async (e) => {
      state.treeFilter.showAll = e.target.checked;
      if (state.treeFilter.showAll && !state.fullTree) {
        renderTree(); // Render the loading state immediately
        try {
          state.fullTree = await fetchTree(state.route.slug, state.route.key);
        } catch (err) {
          showToast(err.message);
          state.treeFilter.showAll = false;
        }
      }
      renderTree();
    });
  }
}

// === Content rendering =============================================

function renderContent() {
  // Topbar reflects the navigation cursor counter — keep it in sync with
  // every content render so Tab / button clicks update the "N / 9".
  renderTopbar();
  const content = document.getElementById("content");
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
          <p>Run <code>/code-review</code> in any repo to generate one. Reviews land in <code>~/.reviews/&lt;repo-slug&gt;/</code> and will appear here as soon as they're written. Background jobs that produce reviews show up the same way.</p>
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
    ? `<div class="inbox-empty">No reviews in this bucket. Run <code>/code-review</code> to make one.</div>`
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
        showToast("Deleted");
        loadRoute(state.route);
      } catch (err) {
        showToast(err.message);
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
    if (r.has_review_feedback || r.has_per_comment_feedback) {
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

  const feedback = (r.has_review_feedback || r.has_per_comment_feedback)
    ? `<span class="feedback-flag">feedback</span>` : "";
  const stale = r.stale ? `<span class="stale-flag">stale</span>` : "";

  return `
    <tr class="inbox-row ${r.stale ? "stale" : ""}" data-slug="${r.slug}" data-key="${r.key}">
      <td><span class="repo">${escapeHtml(r.repo_name)}</span> ${stale}</td>
      <td><span class="branch">${escapeHtml(r.branch || "—")}</span></td>
      <td><span class="sha">${escapeHtml(r.short_sha)}</span></td>
      <td>${pipsHtml} ${feedback}</td>
      <td><span class="age">${relativeAge(r.modified)}</span></td>
      <td>${r.pr_number ? `<span class="pr">#${escapeHtml(r.pr_number)}</span>` : `<span class="pr none">—</span>`}</td>
      <td><button class="inbox-delete" title="Delete review" data-slug="${r.slug}" data-key="${r.key}"><i data-lucide="trash-2"></i></button></td>
    </tr>
  `;
}

// --- Per-review overview ---

function renderReviewOverview() {
  const r = state.review.review;
  const t = state.review.target;
  const grouped = {};
  (r.comments || []).forEach((c) => {
    if (!grouped[c.file]) grouped[c.file] = [];
    grouped[c.file].push(c);
  });

  const groupsHtml = Object.entries(grouped).map(([file, comments]) => `
    <div class="file-group">
      <div class="file-group-header" data-file="${escapeHtml(file)}">
        <i data-lucide="file-text"></i>
        <strong>${escapeHtml(file)}</strong>
        <span>·</span>
        <span>${comments.length} ${comments.length === 1 ? "comment" : "comments"}</span>
      </div>
      <div class="file-group-cards">
        ${comments
          .sort((a, b) => severityOrder(a.severity) - severityOrder(b.severity))
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

    <div class="overview-summary">
      <div class="overview-summary-label">Summary · ${escapeHtml(r.event)}</div>
      <div class="overview-summary-body">${escapeHtml(r.summary)}</div>
    </div>

    <div class="overview-feedback">
      <div class="overview-summary-label">Review-level feedback (read on next /code-review run)</div>
      <textarea id="review-feedback-input" placeholder="Notes for the AI to address on the next iteration…">${escapeHtml(r.feedback || "")}</textarea>
    </div>

    <div class="overview-comments-label">${(r.comments || []).length} comments across ${Object.keys(grouped).length} files</div>
    ${groupsHtml}
  `;

  attachContentHandlers();
  if (window.lucide) window.lucide.createIcons();
}

// --- Per-file view ---

function renderFileView() {
  const filePath = state.route.file;
  const language = detectLanguage(filePath, state.source?.content);
  const source = state.source?.content || "(file content not available)";
  const lines = source.split("\n");
  const fileComments = (state.review.review?.comments || [])
    .filter((c) => c.file === filePath)
    .sort((a, b) => commentLineRange(a)[0] - commentLineRange(b)[0]);

  const commentsAtLine = new Map();
  const rangedSpanLines = new Set();
  fileComments.forEach((c) => {
    const [s, e] = commentLineRange(c);
    if (!commentsAtLine.has(s)) commentsAtLine.set(s, []);
    commentsAtLine.get(s).push(c);
    for (let i = s; i <= e; i++) rangedSpanLines.add(i);
  });

  const rows = lines.map((lineText, idx) => {
    const lineNum = idx + 1;
    const anchored = commentsAtLine.get(lineNum) || [];
    const inRange = rangedSpanLines.has(lineNum);

    let markerHtml = "";
    if (anchored.length > 0) {
      const c = anchored[0];
      markerHtml = `<span class="dot" style="background:${severityColorVar(c.severity)}"></span>`;
    }

    const markerClass = anchored.length > 0 ? `gutter-marker has-marker`
      : inRange ? `gutter-marker range-mid` : "gutter-marker";
    const isUncommented = anchored.length === 0 && !inRange;
    const rowClass = [
      anchored.length > 0 ? "has-comment" : "",
      inRange && anchored.length === 0 ? "range-spanned" : "",
      isUncommented ? "uncommented" : "",
    ].filter(Boolean).join(" ");
    const codeHtml = renderHighlightedLine(lineText, language);
    const gutterDataAttr = anchored.length > 0
      ? `data-comment-id="${escapeHtml(anchored[0].id)}"`
      : `data-add-line="${lineNum}"`;

    let html = `
      <tr class="${rowClass}">
        <td class="gutter-num">${lineNum}</td>
        <td class="${markerClass}" ${gutterDataAttr}>${markerHtml}</td>
        <td class="code-cell">${codeHtml}</td>
      </tr>
    `;

    anchored.forEach((c) => {
      if (state.expandedComments.has(c.id)) {
        html += `
          <tr class="comment-row" data-comment-row-id="${escapeHtml(c.id)}">
            <td colspan="3"><div class="comment-row-inner">${renderCommentCard(c, { fileLanguage: language, sourceLines: lines })}</div></td>
          </tr>
        `;
      }
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
  }).join("");

  document.getElementById("content").innerHTML = `
    <div class="code-pane">
      <div class="code-header">
        <i data-lucide="file-text"></i>
        <strong>${escapeHtml(filePath)}</strong>
        <span class="lang-badge">${language || "auto"}</span>
        <span style="margin-left:auto">${fileComments.length} ${fileComments.length === 1 ? "comment" : "comments"}</span>
      </div>
      <div class="code-table-scroll">
        <table class="code-table"><tbody>${rows}</tbody></table>
      </div>
    </div>
  `;
  attachContentHandlers();
  if (window.lucide) window.lucide.createIcons();
}

function severityColorVar(sev) {
  return `var(--sev-${sev})`;
}

// --- New comment form ---

function renderNewCommentForm() {
  const t = state.newCommentTarget;
  const language = detectLanguage(t.file, state.source?.content);
  const initialSuggestion = originalTextForNewComment();
  return `
    <div class="new-comment-form" data-new-comment-form>
      <div class="form-row">
        <span class="comment-line-ref">L${t.line}${t.isRange && t.endLine ? `–${t.endLine}` : ""}</span>
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
        <input type="text" id="new-category" placeholder="category (correctness, security, perf, style, …)" />
      </div>
      <textarea id="new-body" placeholder="Comment body. Markdown — backticks for inline code."></textarea>
      <div class="comment-editor-preview" id="new-body-preview"></div>
      <div class="comment-suggestion">
        <div class="comment-suggestion-label">
          <i data-lucide="lightbulb"></i>
          Suggested change
        </div>
        <textarea id="new-suggestion" class="suggestion" data-suggestion-language="${escapeHtml(language || "")}" placeholder="Optional suggested change. Raw code — no fences. Replaces the line${t.isRange ? "s" : ""} above.">${escapeHtml(initialSuggestion)}</textarea>
        <div class="suggestion-warning" id="new-suggestion-warning" hidden></div>
        <div class="suggestion-preview" id="new-suggestion-preview"></div>
      </div>
      <div class="form-actions">
        <button class="btn btn-primary" data-save-new>
          <i data-lucide="plus"></i>
          Add comment
        </button>
      </div>
    </div>
  `;
}

function nextCommentId() {
  const ids = (state.review.review.comments || []).map((c) => c.id);
  let max = 0;
  ids.forEach((id) => {
    const m = /^rev-(\d+)$/.exec(id);
    if (m) max = Math.max(max, parseInt(m[1], 10));
  });
  return `rev-${String(max + 1).padStart(3, "0")}`;
}

// --- Comment card ---

function renderCommentCard(c, opts = {}) {
  const [s, e] = commentLineRange(c);
  const lineRef = s === e ? `L${s}` : `L${s}–${e}`;
  const sev = c.severity || "info";
  const language = opts.fileLanguage || detectLanguage(c.file);

  // Severity / status / id are *expected* to be enum / pattern values, but
  // validate.py is only run at generation time — a malicious YAML written
  // into ~/.reviews/ by some other tool could carry any string. Escape
  // every interpolation that lands in attributes or text content.
  const sevSafe = escapeHtml(sev);
  const statusSafe = escapeHtml(c.status);
  const idSafe = escapeHtml(c.id);

  const isEditingSuggestion = state.editingSuggestion === c.id;
  let suggestionHtml = "";
  if (isEditingSuggestion) {
    const draft = c.suggestion || state.suggestionDrafts.get(c.id) || "";
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
        <div class="comment-body-edit-hint">Cmd/Ctrl+Enter to save · Esc to cancel · empty to remove</div>
      </div>
    `;
  } else if (c.suggestion) {
    suggestionHtml = renderSuggestionDiff(c, language, opts.sourceLines, idSafe);
  } else {
    // No suggestion yet — offer a way to add one.
    suggestionHtml = `
      <button class="btn btn-suggestion-add" data-edit-suggestion-target="${idSafe}">
        <i data-lucide="lightbulb"></i>
        Add suggested change
      </button>
    `;
  }

  const feedbackHtml = c.feedback ? `
    <div class="comment-feedback">
      <div class="comment-feedback-label">
        <i data-lucide="message-square-warning"></i>
        Feedback (read on next /code-review run)
      </div>
      <div class="comment-feedback-text">${escapeHtml(c.feedback)}</div>
    </div>
  ` : `
    <textarea class="comment-feedback-input" data-comment-feedback="${idSafe}" placeholder="Leave feedback for the AI to address on the next /code-review run…"></textarea>
  `;

  const lineRefHtml = opts.withLineRef ? `<span class="comment-line-ref">${lineRef}</span>` : "";
  const closeBtnHtml = opts.withLineRef ? "" :
    `<button class="comment-close" data-collapse-comment="${idSafe}" title="Close (Esc)"><i data-lucide="x"></i></button>`;

  const isEditing = state.editingBody === c.id;
  const bodyHtml = isEditing
    ? `
      <textarea class="comment-body-edit" data-edit-body="${idSafe}" autofocus>${escapeHtml(c.body)}</textarea>
      <div class="comment-editor-preview" data-markdown-preview-for="${idSafe}">${renderMarkdown(c.body)}</div>
      <div class="comment-body-edit-hint">Cmd/Ctrl+Enter to save · Esc to cancel</div>
    `
    : `<div class="comment-body" data-edit-target="${idSafe}" title="Click to edit">${renderMarkdown(c.body)}</div>`;

  return `
    <div class="comment-card" data-comment-card="${idSafe}">
      <div class="comment-header">
        <span class="severity-badge ${sevSafe}">${sevSafe}</span>
        <span class="category-pill">${escapeHtml(c.category)}</span>
        <button class="status-pill ${statusSafe}" data-cycle-status="${idSafe}" title="Click to cycle: open → acknowledged → resolved → wontfix">${statusSafe}</button>
        ${lineRefHtml}
        <span class="comment-id">${idSafe}</span>
        ${closeBtnHtml}
      </div>
      ${bodyHtml}
      ${suggestionHtml}
      ${feedbackHtml}
      <div class="comment-actions">
        <button class="btn btn-icon btn-danger" data-delete-comment="${idSafe}" title="Delete comment">
          <i data-lucide="trash-2"></i>
        </button>
        <div class="spacer"></div>
        <button class="btn" data-save-comment-feedback="${idSafe}">
          <i data-lucide="save"></i>
          Save feedback
        </button>
        <button class="btn btn-primary" data-send-comment="${idSafe}" ${state.review.target?.pr_number ? "" : "disabled"}>
          <i data-lucide="send"></i>
          Send this comment
        </button>
      </div>
    </div>
  `;
}

function renderSuggestionDiff(c, language, sourceLinesArg, idSafe) {
  const [s] = commentLineRange(c);
  const originalText = originalTextForComment(c, sourceLinesArg);

  return `
    <div class="comment-suggestion">
      <div class="comment-suggestion-label">
        <i data-lucide="lightbulb"></i>
        Suggested change
        <button class="suggestion-edit-btn" data-edit-suggestion-target="${idSafe}" title="Edit suggestion">
          <i data-lucide="pencil"></i>
        </button>
      </div>
      ${renderSuggestionDiffTable(originalText, c.suggestion || "", language, s)}
    </div>
  `;
}

// === Mutation helpers ==============================================

async function persistReview() {
  const { _slug, _key, ...payload } = state.review;
  await putReview(state.route.slug, state.route.key, payload);
}

async function saveEditedBody(id, newBody) {
  const c = state.review.review.comments.find((x) => x.id === id);
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
    renderContent();
    showToast(`Edited ${id}`);
  } catch (err) {
    c.body = original;
    showToast(err.message);
  }
}

function cancelBodyEdit() {
  state.editingBody = null;
  renderContent();
}

async function beginSuggestionEdit(id) {
  const c = state.review.review.comments.find((x) => x.id === id);
  if (!c) return;
  let source = null;
  try {
    source = await ensureSourceForFile(c.file);
  } catch (err) {
    showToast(err.message || "Could not load source for suggestion");
  }
  if (!c.suggestion && !state.suggestionDrafts.has(id)) {
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
  const c = state.review.review.comments.find((x) => x.id === id);
  if (!c) return;
  const hadSuggestion = Boolean(c.suggestion);
  const originalSuggestion = c.suggestion;
  const newSuggestion = normalizeSuggestionText(rawValue);
  const originalSourceText = originalTextForComment(c);
  const isUnchangedDraft = !hadSuggestion && newSuggestion === originalSourceText;
  const finalSuggestion = isUnchangedDraft ? "" : newSuggestion;

  if ((finalSuggestion || "") === (c.suggestion || "")) {
    state.editingSuggestion = null;
    state.suggestionDrafts.delete(id);
    renderContent();
    return;
  }

  if (finalSuggestion) c.suggestion = finalSuggestion;
  else delete c.suggestion;
  try {
    await persistReview();
    state.editingSuggestion = null;
    state.suggestionDrafts.delete(id);
    renderContent();
    showToast(finalSuggestion ? `Edited suggestion on ${id}` : `Removed suggestion from ${id}`);
  } catch (err) {
    if (originalSuggestion !== undefined) c.suggestion = originalSuggestion;
    else delete c.suggestion;
    showToast(err.message);
  }
}

function cancelSuggestionEdit(id) {
  state.editingSuggestion = null;
  state.suggestionDrafts.delete(id);
  renderContent();
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
        renderContent();
      },
      onChange: (value) => updateSuggestionPreview(previewEl, warningEl, originalText, value, language, t.line),
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
    const c = state.review.review.comments.find((x) => x.id === id);
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
  initializeEditors(content);

  content.querySelectorAll("[data-comment-id]").forEach((el) => {
    el.addEventListener("click", () => {
      toggleComment(el.getAttribute("data-comment-id"));
    });
  });

  // Click on uncommented gutter → open new-comment form on that line
  content.querySelectorAll("[data-add-line]").forEach((el) => {
    el.addEventListener("click", () => {
      const line = parseInt(el.getAttribute("data-add-line"), 10);
      state.newCommentTarget = {
        file: state.route.file,
        line,
        isRange: false,
        endLine: line,
      };
      renderContent();
      requestAnimationFrame(() => {
        const bodyEl = document.getElementById("new-body");
        if (bodyEl?._cm) bodyEl._cm.focus();
        else bodyEl?.focus();
      });
    });
  });

  // New-comment form handlers
  content.querySelectorAll("[data-cancel-new]").forEach((el) => {
    el.addEventListener("click", () => {
      state.newCommentTarget = null;
      renderContent();
    });
  });
  content.querySelectorAll("#new-range-toggle").forEach((el) => {
    el.addEventListener("change", (e) => {
      state.newCommentTarget.isRange = e.target.checked;
      if (!state.newCommentTarget.isRange) {
        state.newCommentTarget.endLine = state.newCommentTarget.line;
      }
      renderContent();
    });
  });
  content.querySelectorAll("[data-save-new]").forEach((el) => {
    el.addEventListener("click", async () => {
      const t = state.newCommentTarget;
      const bodyEl = document.getElementById("new-body");
      const suggestionEl = document.getElementById("new-suggestion");
      const body = editorValue(bodyEl).trim();
      const category = document.getElementById("new-category").value.trim() || "correctness";
      const severity = document.getElementById("new-severity").value;
      const suggestion = normalizeSuggestionText(editorValue(suggestionEl));
      const endLineEl = document.getElementById("new-end-line");
      const endLine = t.isRange && endLineEl ? parseInt(endLineEl.value, 10) : t.line;
      const originalSuggestion = sourceTextForRange(t.file, t.line, endLine);

      if (!body) {
        showToast("Comment body is required");
        return;
      }
      if (t.isRange && endLine < t.line) {
        showToast("End line must be ≥ start line");
        return;
      }

      const newComment = {
        id: nextCommentId(),
        file: t.file,
        line: endLine,
        severity,
        category,
        body,
        status: "open",
      };
      if (t.isRange && endLine !== t.line) newComment.start_line = t.line;
      if (suggestion && suggestion !== originalSuggestion) newComment.suggestion = suggestion;

      state.review.review.comments.push(newComment);
      try {
        await persistReview();
        state.newCommentTarget = null;
        state.expandedComments.add(newComment.id);
        renderTree();
        renderContent();
        showToast(`Added ${newComment.id}`);
      } catch (err) {
        showToast(err.message);
        // Roll back optimistic update
        state.review.review.comments = state.review.review.comments.filter((c) => c.id !== newComment.id);
      }
    });
  });

  // Click body → enter edit mode
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

  // Edit-suggestion keyboard handlers (Cmd/Ctrl+Enter saves, Esc cancels,
  // empty textarea on save removes the suggestion entirely).
  content.querySelectorAll("[data-edit-suggestion]").forEach((el) => {
    el.addEventListener("keydown", async (e) => {
      const id = el.getAttribute("data-edit-suggestion");
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault();
        await saveEditedSuggestion(id, editorValue(el));
      } else if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
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

  content.querySelectorAll(".file-group-header[data-file]").forEach((el) => {
    el.addEventListener("click", () => {
      navigate({
        view: "file",
        slug: state.route.slug,
        key: state.route.key,
        file: el.getAttribute("data-file"),
      });
    });
  });

  content.querySelectorAll("[data-cycle-status]").forEach((el) => {
    el.addEventListener("click", async (e) => {
      e.stopPropagation();
      const id = el.getAttribute("data-cycle-status");
      cycleStatus(id);
    });
  });

  content.querySelectorAll("[data-delete-comment]").forEach((el) => {
    el.addEventListener("click", async () => {
      const id = el.getAttribute("data-delete-comment");
      if (!confirm(`Delete comment ${id}?`)) return;
      state.review.review.comments = state.review.review.comments.filter((c) => c.id !== id);
      try {
        await persistReview();
        renderTree();
        renderContent();
        showToast(`Deleted ${id}`);
      } catch (err) {
        showToast(err.message);
      }
    });
  });

  content.querySelectorAll("[data-save-comment-feedback]").forEach((el) => {
    el.addEventListener("click", async () => {
      const id = el.getAttribute("data-save-comment-feedback");
      const ta = content.querySelector(`[data-comment-feedback="${id}"]`);
      const c = state.review.review.comments.find((x) => x.id === id);
      if (!ta || !c) return;
      c.feedback = ta.value;
      try {
        await persistReview();
        renderContent();
        showToast(`Feedback saved on ${id}`);
      } catch (err) {
        showToast(err.message);
      }
    });
  });

  content.querySelectorAll("[data-send-comment]").forEach((el) => {
    el.addEventListener("click", async () => {
      const id = el.getAttribute("data-send-comment");
      if (!state.review.target?.pr_number) {
        showToast("No PR — set target.pr_number to enable sending");
        return;
      }
      try {
        await submitReview(state.route.slug, state.route.key, { mode: "comment", commentId: id });
        // Reload the review (server removed the comment).
        state.review = null;
        await loadRoute(state.route);
        showToast(`Sent ${id}`);
      } catch (err) {
        showToast(err.message);
      }
    });
  });
}

async function toggleComment(id) {
  if (state.expandedComments.has(id)) {
    state.expandedComments.delete(id);
  } else {
    state.expandedComments.add(id);
    state.cursorCommentId = id;
  }
  renderContent();
  scrollCommentIntoView(id);
}

// Pixels of breathing room between the topbar and the top of a navigated
// comment card. Bigger = more code context visible above the comment (useful
// in code-file view); smaller = comment dominates the viewport.
const COMMENT_SCROLL_TOP_OFFSET = 120;

function scrollCommentIntoView(id) {
  requestAnimationFrame(() => {
    const card = document.querySelector(`[data-comment-card="${id}"]`);
    const content = document.getElementById("content");
    if (!card || !content) return;
    // Manual scrollTop math instead of scrollIntoView({block:"center"}):
    // a tall expanded card centered in the viewport puts its header above
    // the topbar, hiding the comment's most important line. Anchor the top
    // edge at a fixed offset from .content's top instead.
    const top =
      card.getBoundingClientRect().top -
      content.getBoundingClientRect().top +
      content.scrollTop -
      COMMENT_SCROLL_TOP_OFFSET;
    content.scrollTo({ top, behavior: "smooth" });
  });
}

async function cycleStatus(commentId) {
  const order = ["open", "acknowledged", "resolved", "wontfix"];
  const c = state.review.review.comments.find((x) => x.id === commentId);
  if (!c) return;
  c.status = order[(order.indexOf(c.status) + 1) % order.length];
  try {
    await persistReview();
    renderContent();
  } catch (err) {
    showToast(err.message);
  }
}

// === Topbar actions ================================================

document.getElementById("btn-home").addEventListener("click", () => {
  navigate({ view: "inbox" });
});

document.getElementById("btn-prev-comment").addEventListener("click", () => {
  navigateToComment(-1);
});

document.getElementById("btn-next-comment").addEventListener("click", () => {
  navigateToComment(+1);
});

document.getElementById("btn-save-feedback").addEventListener("click", async () => {
  const ta = document.getElementById("review-feedback-input");
  if (!ta || !state.review) {
    showToast("Open the review overview to edit review-level feedback");
    return;
  }
  state.review.review.feedback = ta.value;
  try {
    await persistReview();
    showToast("Review-level feedback saved");
  } catch (err) {
    showToast(err.message);
  }
});

document.getElementById("btn-send-review").addEventListener("click", async () => {
  if (!state.review?.target?.pr_number) {
    showToast("No PR — set target.pr_number to enable sending");
    return;
  }
  if (!confirm("Send all open + acknowledged comments to GitHub?")) return;
  try {
    const res = await submitReview(state.route.slug, state.route.key, { mode: "all" });
    showToast(`Sent · ${res.url || ""}`);
    navigate({ view: "inbox" });
  } catch (err) {
    showToast(err.message);
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
  state.review.review.comments.forEach((c) => {
    if (!grouped[c.file]) grouped[c.file] = [];
    grouped[c.file].push(c);
  });
  return Object.entries(grouped)
    .sort(([a], [b]) => a.localeCompare(b))
    .flatMap(([, group]) =>
      group.sort((a, b) => commentLineRange(a)[0] - commentLineRange(b)[0]),
    );
}

async function navigateToComment(direction) {
  if (state.route.view === "inbox") return;
  const comments = navigableComments();
  if (comments.length === 0) return;

  // Use the explicit cursor instead of inferring from `expandedComments`. The
  // Set's iteration order is insertion order, so clicking comments in any
  // sequence and then tabbing was breaking the cycle (the "first" expanded id
  // no longer matched the visually-current comment).
  const currentIdx = state.cursorCommentId
    ? comments.findIndex((c) => c.id === state.cursorCommentId)
    : -1;

  const nextIdx = currentIdx === -1
    ? (direction > 0 ? 0 : comments.length - 1)
    : (currentIdx + direction + comments.length) % comments.length;

  const target = comments[nextIdx];
  state.cursorCommentId = target.id;

  if (state.route.view !== "file" || state.route.file !== target.file) {
    // navigate() → loadRoute() clears expandedComments, so wait for it before
    // expanding the target — otherwise the target ends up collapsed.
    await navigate({ view: "file", slug: state.route.slug, key: state.route.key, file: target.file });
  }
  state.expandedComments.clear();
  state.expandedComments.add(target.id);
  renderContent();
  scrollCommentIntoView(target.id);
}

document.addEventListener("keydown", (e) => {
  if (isTypingInInput()) {
    if (e.key === "Escape") {
      document.activeElement.blur();
      e.preventDefault();
    }
    return;
  }

  if (e.key === "Tab" && !e.shiftKey) {
    e.preventDefault();
    navigateToComment(+1);
  } else if (e.key === "Tab" && e.shiftKey) {
    e.preventDefault();
    navigateToComment(-1);
  } else if (e.key === "j") {
    e.preventDefault();
    navigateToComment(+1);
  } else if (e.key === "k") {
    e.preventDefault();
    navigateToComment(-1);
  } else if (e.key === "Escape") {
    if (state.newCommentTarget) {
      state.newCommentTarget = null;
      renderContent();
    } else if (state.expandedComments.size > 0) {
      state.expandedComments.clear();
      renderContent();
    }
  } else if (e.key === "?") {
    showToast("Keys: Tab/S-Tab or j/k → next/prev comment · Esc → close");
  }
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
