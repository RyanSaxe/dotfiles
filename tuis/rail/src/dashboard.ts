import { rank, type Ranked } from "./search.js";
import { bg, blend, fg, loadPalette, RESET, type Palette } from "./theme.js";

export type DashboardSurface = "reviews" | "tasks";

// What an item needs attention FOR. The hue follows the object, per the
// locked semantics: CI failure is red, pull-request activity peach, issue
// activity mauve.
export type DashboardTone = "ci" | "pull_request" | "issue" | "neutral";

// The selected item's panel, in the shape the design settled on: a headline
// naming the trigger, the specifics beneath it, then dim context. `bullets`
// carries failing check names and nothing else — passing checks are noise on
// a row you are only looking at because something broke.
export interface DashboardPreview {
  headline: string;
  bullets: readonly string[];
  body: readonly string[];
  context: readonly string[];
}

export interface DashboardItem {
  id: string;
  // owner/name. Rows are grouped under it, so it is a heading, not a column.
  repository: string;
  reference: string;
  // Who triggered this. Blank where GitHub sends no actor (CI, review
  // requests) — Author covers those cases.
  from: string;
  // Who opened the PR or issue. Always present, dimmed when it is you, so a
  // column of your own name never competes for attention.
  author: string;
  authorIsViewer: boolean;
  reason: string;
  time: string;
  title: string;
  url: string | null;
  tone: DashboardTone;
  preview: DashboardPreview;
}

export interface DashboardData {
  surface: DashboardSurface;
  items: readonly DashboardItem[];
  status: string;
  emptyMessage: string;
  error: string | null;
}

export interface DashboardHandlers {
  refresh(): Promise<DashboardData>;
  open(item: DashboardItem): Promise<void>;
  browser(item: DashboardItem): Promise<void>;
  acknowledge(item: DashboardItem): Promise<void>;
}

type DashboardKey =
  | "up"
  | "down"
  | "open"
  | "browser"
  | "acknowledge"
  | "refresh"
  | "scrollUp"
  | "scrollDown"
  | "quit"
  | null;

interface Cell {
  text: string;
  color?: string;
}

const ESC = "\x1b";
const HIDE_CURSOR = `${ESC}[?25l`;
const SHOW_CURSOR = `${ESC}[?25h`;
const ALT_SCREEN = `${ESC}[?1049h`;
const MAIN_SCREEN = `${ESC}[?1049l`;
const CLEAR = `${ESC}[2J${ESC}[H`;

// What a people column shows when GitHub gives no one to name.
export const EMPTY_CELL = "—";

// Half a small panel: enough that Ctrl-d feels like paging, small enough
// that nothing scrolls past unseen.
const PREVIEW_SCROLL = 6;

function widthOf(text: string): number {
  return Array.from(text).length;
}

function clip(text: string, width: number): string {
  if (width <= 0) return "";
  if (widthOf(text) <= width) return text;
  if (width === 1) return "…";
  return `${Array.from(text)
    .slice(0, width - 1)
    .join("")}…`;
}

function padded(text: string, width: number): string {
  const clipped = clip(text, width);
  return clipped + " ".repeat(Math.max(0, width - widthOf(clipped)));
}

function surfaceLabel(surface: DashboardSurface): string {
  return surface === "reviews" ? "Reviews" : "Tasks";
}

function background(palette: Palette): string {
  return palette.base;
}

function ruleColor(palette: Palette): string {
  return blend(palette.lavender, background(palette), 0.45);
}

function mutedColor(palette: Palette): string {
  return blend(palette.dim, background(palette), 0.72);
}

function toneColor(tone: DashboardTone, palette: Palette): string {
  switch (tone) {
    case "ci":
      return palette.red;
    case "pull_request":
      return palette.peach;
    case "issue":
      return palette.mauve;
    case "neutral":
      return palette.text;
  }
}

function content(
  width: number,
  palette: Palette,
  cells: Cell[],
  lineBackground = background(palette),
): string {
  let remaining = width;
  let output = bg(lineBackground);
  for (const cell of cells) {
    if (remaining <= 0) break;
    const text = clip(cell.text, remaining);
    output += fg(cell.color ?? palette.text) + text;
    remaining -= widthOf(text);
  }
  output += " ".repeat(Math.max(0, remaining));
  return output + RESET;
}

function line(
  width: number,
  palette: Palette,
  cells: Cell[],
  lineBackground = background(palette),
): string {
  return content(width, palette, cells, lineBackground);
}

function rightAlignedLine(
  width: number,
  palette: Palette,
  left: Cell[],
  rightText: string,
): string {
  const rightWidth = widthOf(rightText);
  const gap = 2;
  const leftWidth = Math.max(0, width - rightWidth - gap);
  const leftText = left.map((cell) => cell.text).join("");
  return line(width, palette, [
    ...left,
    { text: " ".repeat(Math.max(0, leftWidth - widthOf(leftText))) },
    { text: " ".repeat(gap) },
    { text: rightText, color: mutedColor(palette) },
  ]);
}

function rule(width: number, palette: Palette, title?: string): string {
  const label = title === undefined ? "" : ` ${title} `;
  return line(width, palette, [
    {
      text: `${label}${"─".repeat(Math.max(0, width - widthOf(label)))}`,
      color: ruleColor(palette),
    },
  ]);
}

function panelRule(
  width: number,
  palette: Palette,
  kind: "top" | "bottom",
  title?: string,
): string {
  const left = kind === "top" ? "╭" : "╰";
  const right = kind === "top" ? "╮" : "╯";
  const label = title === undefined ? "" : ` ${title} `;
  return line(width, palette, [
    {
      text: `${left}${label}${"─".repeat(
        Math.max(0, width - widthOf(label) - 2),
      )}${right}`,
      color: ruleColor(palette),
    },
  ]);
}

// The closing border has to be placed at the panel's edge, not after the
// text. `content` pads at the very end of a line, so without reserving the
// inner width here every preview row ends in a stray `│`.
function panelLine(width: number, palette: Palette, cells: Cell[]): string {
  const inner = Math.max(0, width - 4);
  const clipped: Cell[] = [];
  let remaining = inner;
  for (const cell of cells) {
    if (remaining <= 0) break;
    const text = clip(cell.text, remaining);
    clipped.push({ ...cell, text });
    remaining -= widthOf(text);
  }
  return line(width, palette, [
    { text: "│ ", color: ruleColor(palette) },
    ...clipped,
    { text: " ".repeat(Math.max(0, remaining)) },
    { text: " │", color: ruleColor(palette) },
  ]);
}

// Split one column into runs so the characters a search matched can be
// colored. Positions index the ORIGINAL value; a clipped cell keeps only the
// ones still visible, so the ellipsis never lights up.
function columnCells(
  value: string,
  width: number,
  color: string,
  highlight: string | null,
  positions: readonly number[],
): Cell[] {
  const shown = padded(value, width);
  if (highlight === null || positions.length === 0) {
    return [{ text: shown, color }];
  }
  const source = Array.from(value);
  const marked = new Set(positions);
  const cells: Cell[] = [];
  let run = "";
  let runIsHit = false;
  const flush = (): void => {
    if (run !== "")
      cells.push({ text: run, color: runIsHit ? highlight : color });
    run = "";
  };
  Array.from(shown).forEach((character, index) => {
    const isHit = marked.has(index) && source[index] === character;
    if (isHit !== runIsHit) {
      flush();
      runIsHit = isHit;
    }
    run += character;
  });
  flush();
  return cells;
}

function tableWidths(width: number): number[] {
  const gap = 2;
  // #, PR, From, Author and Age are fixed; the reason column takes the slack
  // because it is the only cell whose content varies in length.
  const fixed = [4, 7, 11, 11];
  const age = 6;
  const reason = Math.max(
    16,
    width - gap * 5 - fixed.reduce((sum, value) => sum + value, 0) - age,
  );
  return [...fixed, reason, age];
}

function tableCells(
  values: string[],
  widths: number[],
  colors: string[],
  gapColor: string,
  highlight?: {
    color: string;
    hits: ReadonlyMap<number, readonly number[]>;
  },
): Cell[] {
  const cells: Cell[] = [];
  values.forEach((value, index) => {
    if (index > 0) cells.push({ text: "  ", color: gapColor });
    cells.push(
      ...columnCells(
        value,
        widths[index] ?? 0,
        colors[index] ?? colors[0] ?? "",
        highlight?.color ?? null,
        highlight?.hits.get(index) ?? [],
      ),
    );
  });
  return cells;
}

function tableHeader(width: number, palette: Palette): string {
  const widths = tableWidths(width);
  const muted = mutedColor(palette);
  return line(
    width,
    palette,
    tableCells(
      ["#", "PR", "From", "Author", "Needs you", "Age"],
      widths,
      Array.from({ length: widths.length }, () => muted),
      muted,
    ),
  );
}

// The repository heading. It appears once per group, so it can afford the
// full owner/name — which matters once watched repositories in other orgs
// appear next to your own.
function tableHeading(
  width: number,
  palette: Palette,
  repository: string,
): string {
  return line(width, palette, [
    { text: " ", color: mutedColor(palette) },
    { text: repository, color: blend(palette.dim2, background(palette), 0.9) },
  ]);
}

function tableItem(
  width: number,
  palette: Palette,
  item: DashboardItem,
  index: number,
  selected: boolean,
  hits: ReadonlyMap<number, readonly number[]> = new Map(),
): string {
  const widths = tableWidths(width);
  const tone = toneColor(item.tone, palette);
  const muted = mutedColor(palette);
  const marker = selected ? "▌" : " ";
  const lineBackground = selected
    ? blend(palette.surface0, background(palette), 0.9)
    : background(palette);
  return line(
    width,
    palette,
    tableCells(
      [
        `${marker}${index + 1}`,
        item.reference,
        item.from,
        item.author,
        item.reason,
        item.time,
      ],
      widths,
      [
        // The selection marker is structure, so it takes the mascot accent.
        // Everything read as language takes a native color.
        selected ? palette.accent : muted,
        selected ? palette.text : blend(palette.text, background(palette), 0.8),
        item.from === EMPTY_CELL ? muted : palette.text,
        item.authorIsViewer ? muted : palette.text,
        tone,
        muted,
      ],
      muted,
      {
        color: palette.yellow,
        // Cell 0 is the row number, so a field at i renders in cell i + 1.
        hits: new Map(
          [...hits].map(([field, positions]) => [field + 1, positions]),
        ),
      },
    ),
    lineBackground,
  );
}

function emptyTableRow(width: number, palette: Palette, text: string): string {
  const muted = mutedColor(palette);
  return line(width, palette, [
    { text: "  ", color: muted },
    { text, color: muted },
  ]);
}

// A rendered table is headings interleaved with items. Selection counts only
// items, so the two are tracked separately and paginated together.
type TableRow =
  | { kind: "heading"; repository: string }
  | { kind: "blank" }
  | { kind: "item"; ordinal: number; entry: RankedItem };

function tableRows(ranked: readonly RankedItem[]): TableRow[] {
  const rows: TableRow[] = [];
  let current: string | null = null;
  ranked.forEach((entry, ordinal) => {
    if (entry.item.repository !== current) {
      if (current !== null) rows.push({ kind: "blank" });
      rows.push({ kind: "heading", repository: entry.item.repository });
      current = entry.item.repository;
    }
    rows.push({ kind: "item", ordinal, entry });
  });
  return rows;
}

// Window the rows so the selected item stays on screen.
function tableWindow(
  rows: readonly TableRow[],
  selected: number,
  limit: number,
): TableRow[] {
  if (rows.length <= limit) return [...rows];
  const at = rows.findIndex(
    (row) => row.kind === "item" && row.ordinal === selected,
  );
  const anchor = at < 0 ? 0 : at;
  let start = Math.min(
    Math.max(0, anchor - Math.floor(limit / 2)),
    Math.max(0, rows.length - limit),
  );
  // Never open a window on a blank spacer: it reads as a rendering fault.
  if (rows[start]?.kind === "blank") start += 1;
  return rows.slice(start, start + limit);
}

function wrapText(text: string, width: number): string[] {
  if (text === "") return [""];
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    if (current === "") {
      current = word;
      continue;
    }
    if (widthOf(`${current} ${word}`) <= width) {
      current += ` ${word}`;
    } else {
      lines.push(current);
      current = word;
    }
  }
  if (current !== "") lines.push(current);
  return lines.flatMap((lineText) => {
    if (widthOf(lineText) <= width) return [lineText];
    const characters = Array.from(lineText);
    const chunks: string[] = [];
    for (let index = 0; index < characters.length; index += width) {
      chunks.push(characters.slice(index, index + width).join(""));
    }
    return chunks;
  });
}

// P2: lead with the trigger, then the specifics, then dim context. Nothing
// here repeats the row — the table already said the repository, number and
// age, and saying them twice is what made the old panel read as a dump.
function previewLines(
  data: DashboardData,
  selected: DashboardItem | undefined,
  palette: Palette,
  query: string,
  width: number,
): Cell[][] {
  const muted = mutedColor(palette);
  if (selected === undefined) {
    return [
      [
        {
          text: query === "" ? data.emptyMessage : `No matches for /${query}`,
          color: muted,
        },
      ],
    ];
  }

  const inner = Math.max(8, width - 6);
  const tone = toneColor(selected.tone, palette);
  const dim = blend(palette.dim, background(palette), 0.85);
  const lines: Cell[][] = [
    [],
    [{ text: selected.preview.headline, color: tone }],
  ];

  if (selected.preview.bullets.length > 0) {
    lines.push([]);
    for (const bullet of selected.preview.bullets) {
      lines.push([
        { text: "  ✗ ", color: tone },
        { text: bullet, color: palette.text },
      ]);
    }
  }

  if (selected.preview.body.length > 0) {
    for (const paragraph of selected.preview.body) {
      lines.push([]);
      for (const wrapped of wrapText(paragraph, inner)) {
        lines.push([{ text: wrapped, color: palette.text }]);
      }
    }
  }

  if (selected.preview.context.length > 0) {
    lines.push([]);
    lines.push([{ text: "─".repeat(Math.min(inner, 48)), color: dim }]);
    for (const entry of selected.preview.context) {
      for (const wrapped of wrapText(entry, inner)) {
        lines.push([{ text: wrapped, color: muted }]);
      }
    }
  }

  lines.push([]);
  return lines;
}

// The Agents footer rhythm: bright key, dim label, dim separator, so the
// two dashboards read as one application.
function footerLine(
  width: number,
  palette: Palette,
  searching: boolean,
  query: string,
  scrollable: boolean,
): string {
  const muted = mutedColor(palette);
  if (searching) {
    return line(width, palette, [
      { text: "/", color: palette.accent },
      { text: query, color: palette.text },
      { text: "▌", color: palette.accent },
      { text: "   Enter", color: palette.text },
      { text: " Apply   ", color: muted },
      { text: "Esc", color: palette.text },
      { text: " Cancel", color: muted },
    ]);
  }
  const keys: Array<[string, string]> = [
    ["/", "Search"],
    ["↑↓", "Navigate"],
    ["↵", "Open"],
    ["b", "Browser"],
    ["x", "Acknowledge"],
    ["r", "Refresh"],
  ];
  if (scrollable) keys.push(["^u/^d", "Preview"]);
  keys.push(["q", "Quit"]);
  const cells: Cell[] = [];
  keys.forEach(([key, label], index) => {
    if (index > 0) cells.push({ text: " │ ", color: ruleColor(palette) });
    cells.push({ text: key, color: palette.text });
    cells.push({ text: ` ${label}`, color: muted });
  });
  return line(width, palette, cells);
}

// The columns the table actually shows, in cell order. The PR/issue body is
// deliberately absent: it is what made every query match, and highlighting a
// match you cannot see is worse than not matching at all.
function searchFields(item: DashboardItem): string[] {
  // Cell order first, so a hit at index i highlights in cell i + 1. Title and
  // repository trail because neither has a cell — the title lives in the
  // preview and the repository is a heading — but both stay searchable.
  return [
    item.reference,
    item.from,
    item.author,
    item.reason,
    item.time,
    item.title,
    item.repository,
  ];
}

export type RankedItem = Ranked<DashboardItem>;

export function rankDashboardItems(
  items: readonly DashboardItem[],
  query: string,
): RankedItem[] {
  return rank(items, query, searchFields);
}

export function renderDashboard(
  data: DashboardData,
  selectedIndex: number,
  palette: Palette,
  columns: number,
  rows: number,
  query = "",
  searching = false,
  previewOffset = 0,
): string {
  const width = Math.max(64, columns);
  const height = Math.max(16, rows);
  const ranked = rankDashboardItems(data.items, query);
  const items = ranked.map((entry) => entry.item);
  const selected = items[selectedIndex];
  const muted = mutedColor(palette);
  const status =
    query.trim() === ""
      ? data.status
      : `${items.length}/${data.items.length} matches`;

  const lines: string[] = [
    // Subtabs, matching the Agents precedent. The active one takes the
    // mascot accent because a highlighted tab is structure, not text.
    rightAlignedLine(
      width,
      palette,
      [
        { text: " ", color: palette.text },
        { text: surfaceLabel(data.surface), color: palette.accent },
        { text: "  │  ", color: ruleColor(palette) },
        { text: "Worktrees", color: muted },
      ],
      query.trim() === "" ? status : `/${query} · ${status}`,
    ),
    rule(width, palette),
    tableHeader(width, palette),
  ];

  const all = tableRows(ranked);
  // Reserve: panel top + bottom + footer, and at least three preview lines.
  const reserved = 3 + 3;
  const limit = Math.max(
    1,
    Math.min(all.length, height - lines.length - reserved),
  );
  const shown = tableWindow(all, selectedIndex, limit);

  if (items.length === 0) {
    lines.push(
      emptyTableRow(
        width,
        palette,
        query === "" ? data.emptyMessage : "No matching items",
      ),
    );
  } else {
    for (const row of shown) {
      if (row.kind === "blank") lines.push(line(width, palette, []));
      else if (row.kind === "heading")
        lines.push(tableHeading(width, palette, row.repository));
      else
        lines.push(
          tableItem(
            width,
            palette,
            row.entry.item,
            row.ordinal,
            row.ordinal === selectedIndex,
            row.entry.hits,
          ),
        );
    }
    if (shown.length < all.length) {
      const hidden =
        all.filter((row) => row.kind === "item").length -
        shown.filter((row) => row.kind === "item").length;
      lines.push(
        line(width, palette, [{ text: `  … ${hidden} more`, color: muted }]),
      );
    }
  }

  // Everything below is fixed height, so the preview can never push the
  // panel border or the footer off the bottom of the popup — which is what
  // a long PR body used to do.
  const previewTitle = selected
    ? `Preview: ${selected.repository}${selected.reference}`
    : `Preview: ${surfaceLabel(data.surface)}`;
  const capacity = Math.max(1, height - lines.length - 3);
  const content = previewLines(data, selected, palette, query, width);
  // When there is more than fits, the last row becomes the scroll indicator,
  // so it costs a line of content rather than covering one.
  const overflows = content.length > capacity;
  const room = overflows ? Math.max(1, capacity - 1) : capacity;
  const maxOffset = Math.max(0, content.length - room);
  const offset = Math.min(Math.max(0, previewOffset), maxOffset);
  const visible = content.slice(offset, offset + room);

  lines.push(panelRule(width, palette, "top", previewTitle));
  for (const previewLine of visible)
    lines.push(panelLine(width, palette, previewLine));
  for (let index = visible.length; index < room; index += 1)
    lines.push(panelLine(width, palette, []));
  if (overflows) {
    // Say how much is left rather than clipping silently.
    const remaining = maxOffset - offset;
    const above = offset > 0 ? `↑ ${offset} above` : "";
    const below =
      remaining > 0
        ? `↓ ${remaining} more line${remaining === 1 ? "" : "s"}`
        : "";
    lines.push(
      panelLine(width, palette, [
        {
          text: [above, below].filter((part) => part !== "").join("   "),
          color: muted,
        },
      ]),
    );
  }
  lines.push(panelRule(width, palette, "bottom"));
  lines.push(footerLine(width, palette, searching, query, maxOffset > 0));

  while (lines.length < height) lines.push(line(width, palette, []));
  return `${CLEAR}${lines.slice(0, height).join("\n")}`;
}

function keyFor(chunk: string): DashboardKey {
  switch (chunk) {
    case "\u001b[A":
    case "k":
      return "up";
    case "\u001b[B":
    case "j":
      return "down";
    case "\r":
    case "\n":
      return "open";
    case "b":
      return "browser";
    // Acknowledge is `x` so Ctrl-u/Ctrl-d can keep their vi meaning on the
    // preview panel.
    case "x":
      return "acknowledge";
    case "\u0015":
      return "scrollUp";
    case "\u0004":
      return "scrollDown";
    case "r":
    case "\u0012":
      return "refresh";
    case "q":
    case "\u001b":
    case "\u0003":
      return "quit";
    default:
      return null;
  }
}

function errorData(data: DashboardData, error: unknown): DashboardData {
  return {
    ...data,
    error: error instanceof Error ? error.message : String(error),
    status: "action failed",
  };
}

export async function runDashboard(
  initial: DashboardData,
  handlers: DashboardHandlers,
): Promise<void> {
  if (
    !process.stdin.isTTY ||
    !process.stdout.isTTY ||
    process.stdin.setRawMode === undefined
  ) {
    throw new Error("dashboard requires an interactive terminal");
  }

  let data = initial;
  let selectedIndex = 0;
  let busy = false;
  let settled = false;
  let query = "";
  let searching = false;
  let previewOffset = 0;
  const input = process.stdin;
  const output = process.stdout;

  const visibleItems = (): DashboardItem[] =>
    rankDashboardItems(data.items, query).map((entry) => entry.item);

  const render = (): void => {
    const maxIndex = Math.max(0, visibleItems().length - 1);
    selectedIndex = Math.min(selectedIndex, maxIndex);
    output.write(
      renderDashboard(
        data,
        selectedIndex,
        loadPalette(),
        output.columns ?? 100,
        output.rows ?? 30,
        query,
        searching,
        previewOffset,
      ),
    );
  };

  await new Promise<void>((resolve, reject) => {
    const cleanup = (): void => {
      input.off("data", onData);
      input.setRawMode?.(false);
      input.pause();
      output.write(`${SHOW_CURSOR}${MAIN_SCREEN}${RESET}`);
    };

    const finish = (): void => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve();
    };

    const runAction = async (
      action: Extract<
        DashboardKey,
        "open" | "browser" | "acknowledge" | "refresh"
      >,
    ): Promise<void> => {
      const item = visibleItems()[selectedIndex];
      if (action !== "refresh" && item === undefined) return;
      busy = true;
      try {
        if (action === "open" && item !== undefined) await handlers.open(item);
        if (action === "browser" && item !== undefined)
          await handlers.browser(item);
        if (action === "acknowledge" && item !== undefined) {
          await handlers.acknowledge(item);
          // The row leaves the table, so the selection would otherwise
          // land on whatever slid up into its place.
          data = await handlers.refresh();
          selectedIndex = Math.max(
            0,
            Math.min(selectedIndex, visibleItems().length - 1),
          );
        }
        if (action === "refresh") data = await handlers.refresh();
      } catch (error) {
        data = errorData(data, error);
      } finally {
        busy = false;
        previewOffset = 0;
        render();
      }
    };

    const onSearchData = (text: string): void => {
      if (text === "\u0003") {
        finish();
        return;
      }
      if (text === "\u001b") {
        searching = false;
        query = "";
        render();
        return;
      }
      if (text === "\r" || text === "\n") {
        searching = false;
        render();
        return;
      }
      if (text === "\u007f" || text === "\u0008") {
        query = Array.from(query).slice(0, -1).join("");
        selectedIndex = 0;
        render();
        return;
      }
      for (const character of text) {
        if (character >= " " && character !== "\u007f") query += character;
      }
      selectedIndex = 0;
      render();
    };

    const onData = (chunk: string | Buffer): void => {
      if (busy) return;
      const text = typeof chunk === "string" ? chunk : chunk.toString("utf8");
      if (searching) {
        onSearchData(text);
        return;
      }
      if (text === "/") {
        searching = true;
        query = "";
        selectedIndex = 0;
        render();
        return;
      }
      const key = keyFor(text);
      if (key === "quit") {
        finish();
        return;
      }
      if (key === "up") {
        selectedIndex = Math.max(0, selectedIndex - 1);
        previewOffset = 0;
        render();
        return;
      }
      if (key === "down") {
        selectedIndex = Math.min(
          Math.max(0, visibleItems().length - 1),
          selectedIndex + 1,
        );
        previewOffset = 0;
        render();
        return;
      }
      // Half-page, the vi meaning. renderDashboard clamps to the real
      // content height, so overscrolling is not possible.
      if (key === "scrollUp") {
        previewOffset = Math.max(0, previewOffset - PREVIEW_SCROLL);
        render();
        return;
      }
      if (key === "scrollDown") {
        previewOffset += PREVIEW_SCROLL;
        render();
        return;
      }
      if (key !== null) void runAction(key);
    };

    input.on("data", onData);
    input.setRawMode(true);
    input.setEncoding("utf8");
    input.resume();
    output.write(`${ALT_SCREEN}${HIDE_CURSOR}`);
    render();

    input.once("error", (error) => {
      cleanup();
      if (!settled) {
        settled = true;
        reject(error);
      }
    });
  });
}
