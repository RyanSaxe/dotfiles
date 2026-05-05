/* ----------------------------------------------------------------
 * code-quality-report / script.js
 *
 * - Renders the findings list from FINDINGS (loaded by data.js)
 * - Wires severity / status filter chips
 * - Status pills cycle on click (open → resolved → wontfix → open)
 * - Copy-to-clipboard for finding IDs
 * - highlight.js does the syntax coloring; styles.css remaps its
 *   .hljs-* classes onto design-system tokens
 * ---------------------------------------------------------------- */

const STATUS_CYCLE = ["open", "resolved", "wontfix"];
const STATUS_LABEL = { open: "Open", resolved: "Resolved", wontfix: "Won't fix" };

// Mutable copy so status toggles persist for the session
const findings = FINDINGS.map((f) => ({ ...f }));
const filters = { severity: "all", status: "all" };

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/* ----------------------------------------------------------------
 * Unified diff renderer
 *
 * Takes the bad and good source plus a language name, returns HTML
 * showing a git-style unified diff with:
 *   - line numbers (old | new) in a gutter
 *   - +/- markers
 *   - per-line red/green backgrounds
 *   - word-level highlights inside changed lines (when an rm chunk
 *     is followed by an add chunk and they have similar content)
 *   - syntax highlighting via hljs on the per-line content
 * ---------------------------------------------------------------- */

function highlightLine(line, language) {
  // hljs on a single line — multi-line constructs degrade gracefully
  if (line === "") return "";
  return hljs.highlight(line, { language, ignoreIllegals: true }).value;
}

function renderWordDiffLine(oldLine, newLine, side, language) {
  // side = "rm" | "add"
  const wordParts = Diff.diffWordsWithSpace(oldLine, newLine);
  const out = [];
  for (const part of wordParts) {
    const isInOldOnly = part.removed;
    const isInNewOnly = part.added;
    const isContext = !isInOldOnly && !isInNewOnly;

    if (side === "rm") {
      if (isInNewOnly) continue;
      const html = highlightLine(part.value, language);
      out.push(isInOldOnly ? `<span class="word-rm">${html}</span>` : html);
    } else {
      if (isInOldOnly) continue;
      const html = highlightLine(part.value, language);
      out.push(isInNewOnly ? `<span class="word-add">${html}</span>` : html);
    }
  }
  return out.join("");
}

function renderUnifiedDiff(bad, good, language, file, lineHint) {
  // Compute line-level diff
  const chunks = Diff.diffLines(bad, good, { newlineIsToken: false });

  // Normalize: each chunk's value may end with a trailing newline; split into lines
  // and strip a single trailing empty entry that comes from the trailing \n.
  const normalize = (chunk) => {
    const lines = chunk.value.split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    return lines;
  };

  // Estimate starting line numbers from the finding's `lines` field ("42-44" or "42")
  const startLine = parseInt(String(lineHint).split(/[-,]/)[0], 10) || 1;
  let oldNum = startLine;
  let newNum = startLine;
  let addCount = 0;
  let rmCount = 0;

  // Walk chunks. When an `rm` is immediately followed by `add`, pair them
  // and run word-diff so the user sees what *actually* changed within the line.
  const rendered = [];
  for (let i = 0; i < chunks.length; i++) {
    const c = chunks[i];
    const next = chunks[i + 1];
    const lines = normalize(c);

    const isPair = c.removed && next && next.added;
    if (isPair) {
      const newLines = normalize(next);
      const minLen = Math.min(lines.length, newLines.length);

      // Removed lines (with word-diff against the paired added line)
      for (let j = 0; j < minLen; j++) {
        rendered.push({
          type: "rm",
          oldNum: oldNum++,
          newNum: null,
          html: renderWordDiffLine(lines[j], newLines[j], "rm", language),
        });
        rmCount++;
      }
      // Leftover removed (rm > add)
      for (let j = minLen; j < lines.length; j++) {
        rendered.push({
          type: "rm",
          oldNum: oldNum++,
          newNum: null,
          html: highlightLine(lines[j], language),
        });
        rmCount++;
      }
      // Added lines (with word-diff against paired removed)
      for (let j = 0; j < minLen; j++) {
        rendered.push({
          type: "add",
          oldNum: null,
          newNum: newNum++,
          html: renderWordDiffLine(lines[j], newLines[j], "add", language),
        });
        addCount++;
      }
      // Leftover added
      for (let j = minLen; j < newLines.length; j++) {
        rendered.push({
          type: "add",
          oldNum: null,
          newNum: newNum++,
          html: highlightLine(newLines[j], language),
        });
        addCount++;
      }
      i++; // skip the paired added chunk
    } else if (c.removed) {
      for (const line of lines) {
        rendered.push({
          type: "rm",
          oldNum: oldNum++,
          newNum: null,
          html: highlightLine(line, language),
        });
        rmCount++;
      }
    } else if (c.added) {
      for (const line of lines) {
        rendered.push({
          type: "add",
          oldNum: null,
          newNum: newNum++,
          html: highlightLine(line, language),
        });
        addCount++;
      }
    } else {
      for (const line of lines) {
        rendered.push({
          type: "ctx",
          oldNum: oldNum++,
          newNum: newNum++,
          html: highlightLine(line, language),
        });
      }
    }
  }

  const linesHtml = rendered
    .map((r) => {
      const cls = r.type === "rm" ? "dl-rm" : r.type === "add" ? "dl-add" : "dl-ctx";
      const marker = r.type === "rm" ? "-" : r.type === "add" ? "+" : " ";
      const oldN = r.oldNum != null ? r.oldNum : "";
      const newN = r.newNum != null ? r.newNum : "";
      return `<div class="dl ${cls}">
        <span class="dl-num">${oldN}</span>
        <span class="dl-num">${newN}</span>
        <span class="dl-marker">${marker}</span>
        <code class="dl-content hljs">${r.html}</code>
      </div>`;
    })
    .join("");

  return `
    <div class="diff-block">
      <div class="diff-block-head">
        <span class="file">
          <i data-lucide="file-code-2" class="inline-icon"></i>
          ${escapeHtml(file)}
        </span>
        <span class="stats">
          <span class="stat-rm">−${rmCount}</span>
          <span class="stat-add">+${addCount}</span>
        </span>
      </div>
      <div class="diff-lines">${linesHtml}</div>
    </div>
  `;
}

function renderFinding(f) {
  return `
    <article class="card finding" data-severity="${f.severity}" data-status="${f.status}" data-id="${f.id}">
      <header class="finding-head">
        <div class="finding-head-main">
          <div class="finding-title-row">
            <span class="sev-badge" data-severity="${f.severity}">
              <span class="dot dot-${f.severity}"></span>${f.severity}
            </span>
            <span class="finding-id">${f.id}</span>
            <h3 class="finding-title">${escapeHtml(f.title)}</h3>
            <span class="finding-rule" title="Rule">${f.rule}</span>
          </div>
          <div class="finding-meta">
            <span class="finding-file">
              <i data-lucide="file-code-2" class="inline-icon"></i>
              ${escapeHtml(f.file)}
            </span>
            <span class="finding-line">line ${f.lines}</span>
          </div>
        </div>

        <div class="finding-actions">
          <button class="status-pill" data-status="${f.status}" type="button"
                  title="Click to cycle status">
            ${STATUS_LABEL[f.status]}
          </button>
          <button class="copy-btn" type="button" data-copy="${f.id}" title="Copy finding ID">
            <i data-lucide="copy" class="inline-icon"></i>
            <span class="copy-label">${f.id}</span>
          </button>
        </div>
      </header>

      <div class="finding-body">
        <p class="finding-desc">${escapeHtml(f.description)}</p>
        ${renderUnifiedDiff(f.bad, f.good, f.language, f.file, f.lines)}
      </div>
    </article>
  `;
}

function applyFilters() {
  return findings.filter((f) => {
    if (filters.severity !== "all" && f.severity !== filters.severity) return false;
    if (filters.status !== "all" && f.status !== filters.status) return false;
    return true;
  });
}

function renderFindings() {
  const visible = applyFilters();
  const root = document.getElementById("findings");

  if (visible.length === 0) {
    root.innerHTML = `
      <div class="card" style="text-align:center; padding: var(--space-8); color: var(--muted);">
        No findings match the current filters.
      </div>
    `;
  } else {
    root.innerHTML = visible.map(renderFinding).join("");
  }

  // Update summary
  const total = findings.length;
  const summary = document.getElementById("filterSummary");
  if (visible.length === total) {
    summary.textContent = `Showing all ${total} findings`;
  } else {
    summary.textContent = `Showing ${visible.length} of ${total} findings`;
  }

  // Code is already highlighted inline by renderUnifiedDiff (per-line).
  // Just (re)create Lucide icons.
  lucide.createIcons();
}

function setupChipGroup(rootId, key) {
  const root = document.getElementById(rootId);
  root.addEventListener("click", (e) => {
    const chip = e.target.closest(".chip");
    if (!chip) return;
    root.querySelectorAll(".chip").forEach((c) => c.classList.remove("is-active"));
    chip.classList.add("is-active");
    filters[key] = chip.dataset.value;
    renderFindings();
  });
}

function setupFindingsInteractions() {
  const root = document.getElementById("findings");

  root.addEventListener("click", (e) => {
    // Status pill cycle
    const pill = e.target.closest(".status-pill");
    if (pill) {
      const article = pill.closest(".finding");
      const id = article.dataset.id;
      const f = findings.find((x) => x.id === id);
      const next = STATUS_CYCLE[(STATUS_CYCLE.indexOf(f.status) + 1) % STATUS_CYCLE.length];
      f.status = next;
      pill.dataset.status = next;
      pill.textContent = STATUS_LABEL[next];
      article.dataset.status = next;
      // If filter is active, may need to re-render to hide/show
      if (filters.status !== "all") {
        renderFindings();
      }
      return;
    }

    // Copy button
    const btn = e.target.closest(".copy-btn");
    if (btn) {
      const text = btn.dataset.copy;
      navigator.clipboard.writeText(text).then(() => {
        btn.classList.add("is-copied");
        const label = btn.querySelector(".copy-label");
        const original = label.textContent;
        label.textContent = "Copied";
        setTimeout(() => {
          btn.classList.remove("is-copied");
          label.textContent = original;
        }, 1200);
      });
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  // Configure highlight.js: only the languages we use
  hljs.configure({ languages: ["python"] });

  setupChipGroup("severityChips", "severity");
  setupChipGroup("statusChips", "status");
  setupFindingsInteractions();
  renderFindings();
});
