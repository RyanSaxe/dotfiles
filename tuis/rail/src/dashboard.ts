import { rank, type Ranked } from "./search.js";
import { bg, blend, fg, loadPalette, RESET, type Palette } from "./theme.js";

export type DashboardSurface = "reviews" | "tasks";

// Reviews has two views: the inbox, and the workspaces you have opened from
// it. They are subtabs of one dashboard rather than separate popups, which is
// what makes Enter feel like moving an item rather than losing it.
export type DashboardView = "reviews" | "worktrees";

// What an item needs attention FOR. The hue follows the object, per the
// locked semantics: CI failure is red, pull-request activity peach, issue
// activity mauve.
export type DashboardTone =
  "ci" | "pull_request" | "issue" | "clean" | "neutral";

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

// A metadata run carries meaning, not a colour: the table maps tones to the
// palette so the data layer never needs to know a hex.
export type MetaTone = "add" | "delete" | "change" | "muted";

export interface MetaSpan {
  text: string;
  tone: MetaTone;
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
  // Diff size for a pull request, labels for an issue.
  metadata: readonly MetaSpan[];
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
  // The Worktrees view, rebuilt on demand. Absent for surfaces that have no
  // second view.
  worktrees?(): Promise<DashboardData>;
  // Move the client to an open workspace.
  focus?(item: DashboardItem): Promise<void>;
  // Remove a workspace. Resolves with a reason when it declines.
  cleanup?(item: DashboardItem): Promise<string | null>;
  // Add or focus a reviewer alongside the human review window.
  assist?(item: DashboardItem): Promise<void>;
  // Resolves true when the dashboard should stand aside — opening a review
  // workspace switches the tmux client, and the popup has to be gone for you
  // to land in it.
  open(item: DashboardItem): Promise<boolean>;
  browser(item: DashboardItem): Promise<void>;
  acknowledge(item: DashboardItem): Promise<void>;
  // Pre-coloured diff lines, or a single explanatory line for anything that
  // has no diff. Never null — an empty result would look like a hang.
  diff(item: DashboardItem): Promise<string[]>;
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
  | "diff"
  | "back"
  | "view"
  | "cleanup"
  | "assist"
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

// Escape sequences occupy no columns. Anything that measures a line which
// may carry colour has to strip them first, or every border lands wrong.
const ANSI = /\x1b\[[0-9;?]*[ -/]*[@-~]/g;

// Colour is welcome inside our layout; cursor movement and erase are not.
// Delta ends its lines with `\x1b[0K`, which erases to the right edge and
// would wipe the padding and background we just drew. Keep SGR, drop the
// rest.
export function sanitizeAnsi(text: string): string {
  return text.replace(ANSI, (sequence) =>
    sequence.endsWith("m") ? sequence : "",
  );
}

function widthOf(text: string): number {
  return Array.from(text).length;
}

export function visibleWidth(text: string): number {
  return widthOf(text.replace(ANSI, ""));
}

// Clip a coloured line to a column budget without cutting an escape in half.
// Delta does not wrap long content lines even when given --width, so a README
// diff can hand us a 458-column line; letting it through would wrap in the
// terminal and push the footer off the frame.
// Writing into the very last cell of the very last row makes a terminal
// advance, which scrolls the frame and takes the top line with it — the
// header simply disappears. Every line here is padded to full width, so the
// final one gives up a column. What is lost is trailing padding.
export function frameLines(
  lines: readonly string[],
  height: number,
  width: number,
): string {
  const visible = [...lines.slice(0, height)];
  const last = visible.length - 1;
  if (last >= 0) {
    visible[last] = clipAnsi(visible[last] ?? "", Math.max(0, width - 1));
  }
  return visible.join("\n");
}

export function clipAnsi(text: string, width: number): string {
  if (width <= 0) return "";
  if (visibleWidth(text) <= width) return text;
  let out = "";
  let used = 0;
  let index = 0;
  while (index < text.length && used < width) {
    if (text[index] === "\x1b") {
      ANSI.lastIndex = index;
      const match = ANSI.exec(text);
      if (match !== null && match.index === index) {
        out += match[0];
        index += match[0].length;
        continue;
      }
    }
    out += text[index];
    used += 1;
    index += 1;
  }
  return `${out}${RESET}`;
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

function metaColor(tone: MetaTone, palette: Palette): string {
  switch (tone) {
    case "add":
      return palette.diffAdd;
    case "delete":
      return palette.diffDelete;
    case "change":
      return palette.diffChange;
    case "muted":
      return blend(palette.dim2, background(palette), 0.85);
  }
}

function toneColor(tone: DashboardTone, palette: Palette): string {
  switch (tone) {
    case "ci":
      return palette.red;
    case "pull_request":
      return palette.peach;
    case "issue":
      return palette.mauve;
    case "clean":
      // Healthy at a glance, which is what green is for.
      return palette.green;
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
// A pre-coloured line — bat or delta output — placed inside the panel. The
// colours pass through untouched; only the width is measured, so the closing
// border lands in the right column. Reset before the padding so a background
// set by the content cannot bleed into it.
function panelRawLine(width: number, palette: Palette, raw: string): string {
  const inner = Math.max(0, width - 4);
  const body = clipAnsi(sanitizeAnsi(raw), inner);
  const used = visibleWidth(body);
  const rule = ruleColor(palette);
  const panel = background(palette);
  return (
    bg(panel) +
    fg(rule) +
    "│ " +
    RESET +
    bg(panel) +
    body +
    RESET +
    bg(panel) +
    " ".repeat(Math.max(0, inner - used)) +
    fg(rule) +
    " │" +
    RESET
  );
}

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
  const meta = 14;
  const age = 6;
  const reason = Math.max(
    16,
    width - gap * 6 - fixed.reduce((sum, value) => sum + value, 0) - meta - age,
  );
  return [...fixed, reason, meta, age];
}

function tableCells(
  values: Array<string | Cell[]>,
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
    const columnWidth = widths[index] ?? 0;
    if (typeof value === "string") {
      cells.push(
        ...columnCells(
          value,
          columnWidth,
          colors[index] ?? colors[0] ?? "",
          highlight?.color ?? null,
          highlight?.hits.get(index) ?? [],
        ),
      );
      return;
    }
    // A pre-coloured column: each run keeps its own colour, and the cell is
    // padded to width so the columns after it still line up.
    let used = 0;
    for (const cell of value) {
      if (used >= columnWidth) break;
      const text = clip(cell.text, columnWidth - used);
      cells.push({ ...cell, text });
      used += widthOf(text);
    }
    if (used < columnWidth)
      cells.push({ text: " ".repeat(columnWidth - used) });
  });
  return cells;
}

function tableHeader(
  width: number,
  palette: Palette,
  view: DashboardView,
): string {
  const widths = tableWidths(width);
  const muted = mutedColor(palette);
  return line(
    width,
    palette,
    tableCells(
      view === "worktrees"
        ? ["#", "PR", "Session", "Changes", "Pull request", "Diff", "Age"]
        : ["#", "PR", "From", "Author", "Needs you", "Size", "Age"],
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
        item.metadata.map((span) => ({
          text: span.text,
          color: metaColor(span.tone, palette),
        })),
        item.time,
      ],
      widths,
      [
        // The selection marker is structure, so it takes the mascot accent.
        // Everything read as language takes a native color.
        selected ? palette.accent : muted,
        selected ? palette.text : blend(palette.text, background(palette), 0.8),
        item.from === EMPTY_CELL
          ? muted
          : item.from === "open"
            ? palette.green
            : item.from === "closed"
              ? muted
              : palette.text,
        item.authorIsViewer ? muted : palette.text,
        tone,
        muted,
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
  const window = rows.slice(start, start + limit);

  // Scrolled into the middle of a group, the heading is above the window and
  // you lose track of which repository you are looking at. Carry it in.
  if (window[0]?.kind === "item") {
    for (let index = start - 1; index >= 0; index -= 1) {
      const row = rows[index];
      if (row?.kind === "heading") {
        // Drop the row furthest from the selection, not the nearest: taking
        // it off the end would hide the selected row at the bottom of a list.
        return [row, ...window.slice(1)];
      }
    }
  }
  return window;
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
// A panel row is either cells we colour ourselves or a line that already
// carries its own escapes.
type PanelRow = Cell[] | { raw: string };

function previewLines(
  data: DashboardData,
  selected: DashboardItem | undefined,
  palette: Palette,
  query: string,
  width: number,
): PanelRow[] {
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
  const lines: PanelRow[] = [
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
    lines.push([]);
    for (const rendered of selected.preview.body) {
      // bat wraps its own output, so a coloured line passes through as-is —
      // re-wrapping would split an escape sequence. The plain fallback has
      // no escapes and does need wrapping.
      if (!rendered.includes("\x1b") && visibleWidth(rendered) > inner) {
        for (const wrapped of wrapText(rendered, inner)) {
          lines.push({ raw: wrapped });
        }
        continue;
      }
      lines.push({ raw: rendered });
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
//
// Built one column short of the frame. It is the last line, and writing into
// the bottom-right cell makes a terminal advance — which scrolls the frame and
// takes the header with it. Budgeting for that here means the adaptive key
// list accounts for it, instead of a clip later stealing a letter from "Quit".
function footerLine(
  width: number,
  palette: Palette,
  searching: boolean,
  query: string,
  scrollable: boolean,
  view: DashboardView,
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
  // Every key stays bound; the footer only advertises what fits. Ordered
  // least essential first so a narrow frame drops "Refresh" long before it
  // drops "Quit", instead of clipping the line mid-word.
  const optional: Array<[string, string]> =
    view === "worktrees"
      ? [
          ["r", "Refresh"],
          ["/", "Search"],
          ["a", "Assisted"],
          ["X", "Clean up"],
        ]
      : [
          ["r", "Refresh"],
          ["b", "Browser"],
          ["a", "Assisted"],
          ["d", "Diff"],
          ["/", "Search"],
          ["x", "Acknowledge"],
        ];
  // Sticky-ish: when there IS more to read, saying so beats "Refresh".
  if (scrollable) optional.splice(2, 0, ["^u/^d", "Preview"]);
  const essential: Array<[string, string]> =
    view === "worktrees"
      ? [
          ["↑↓", "Navigate"],
          ["↵", "Focus"],
          ["⇥", "Reviews"],
          ["q", "Quit"],
        ]
      : [
          ["↑↓", "Navigate"],
          ["↵", "Open"],
          ["⇥", "Worktrees"],
          ["q", "Quit"],
        ];

  const measure = (entries: Array<[string, string]>): number =>
    entries.reduce(
      (total, [key, label], index) =>
        total + widthOf(key) + widthOf(label) + 1 + (index > 0 ? 3 : 0),
      0,
    );

  let shown = [...optional, ...essential];
  let dropped = 0;
  while (measure(shown) > width && dropped < optional.length) {
    dropped += 1;
    shown = [...optional.slice(dropped), ...essential];
  }
  const keys = shown;

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

// Ranking decides urgency; grouping decides layout. Grouping has to happen
// here rather than at render time so the array IS display order — otherwise
// the row numbers, which are jump targets, come out of sequence.
function groupByRepository(ranked: readonly RankedItem[]): RankedItem[] {
  const groups = new Map<string, RankedItem[]>();
  for (const entry of ranked) {
    const bucket = groups.get(entry.item.repository);
    if (bucket === undefined) groups.set(entry.item.repository, [entry]);
    else bucket.push(entry);
  }
  return [...groups.values()].flat();
}

export function rankDashboardItems(
  items: readonly DashboardItem[],
  query: string,
): RankedItem[] {
  return groupByRepository(rank(items, query, searchFields));
}

// A whole-width line carrying its own colour. The diff view is deliberately
// full-bleed: the tmux popup already draws a border, and without side
// borders there is no padding arithmetic to get wrong.
function fullWidthRawLine(
  width: number,
  palette: Palette,
  raw: string,
): string {
  const clipped = clipAnsi(sanitizeAnsi(raw), width);
  const used = visibleWidth(clipped);
  return (
    bg(background(palette)) +
    clipped +
    RESET +
    bg(background(palette)) +
    " ".repeat(Math.max(0, width - used)) +
    RESET
  );
}

export function renderDiffView(
  title: string,
  diffLines: readonly string[],
  offset: number,
  palette: Palette,
  columns: number,
  rows: number,
): string {
  const width = Math.max(64, columns);
  const height = Math.max(16, rows);
  const muted = mutedColor(palette);
  const capacity = Math.max(1, height - 3);
  const maxOffset = Math.max(0, diffLines.length - capacity);
  const at = Math.min(Math.max(0, offset), maxOffset);

  const lines: string[] = [
    line(width, palette, [
      { text: " ", color: palette.text },
      { text: title, color: palette.text },
    ]),
    rule(width, palette),
  ];
  for (const raw of diffLines.slice(at, at + capacity)) {
    lines.push(fullWidthRawLine(width, palette, raw));
  }
  while (lines.length < height - 1) lines.push(line(width, palette, []));

  const position =
    maxOffset === 0
      ? ""
      : `  ${at + 1}-${Math.min(at + capacity, diffLines.length)} of ${diffLines.length}`;
  const keys: Array<[string, string]> = [
    ["j/k", "Scroll"],
    ["^u/^d", "Page"],
    ["b", "Browser"],
    ["q", "Back"],
  ];
  const cells: Cell[] = [];
  keys.forEach(([key, label], index) => {
    if (index > 0) cells.push({ text: " │ ", color: ruleColor(palette) });
    cells.push({ text: key, color: palette.text });
    cells.push({ text: ` ${label}`, color: muted });
  });
  if (position !== "") cells.push({ text: position, color: muted });
  lines.push(line(width - 1, palette, cells));

  return `${CLEAR}${frameLines(lines, height, width)}`;
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
  view: DashboardView = "reviews",
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
        {
          text: surfaceLabel(data.surface),
          color: view === "reviews" ? palette.accent : muted,
        },
        { text: "  │  ", color: ruleColor(palette) },
        {
          text: "Worktrees",
          color: view === "worktrees" ? palette.accent : muted,
        },
      ],
      query.trim() === "" ? status : `/${query} · ${status}`,
    ),
    rule(width, palette),
    tableHeader(width, palette, view),
  ];

  const all = tableRows(ranked);
  // The preview keeps a floor: panel borders and footer, plus room to read.
  // A long inbox used to take the whole frame and squeeze the panel down to
  // one blank row, which reads as broken rather than as full.
  const previewFloor = 3 + 7;
  const limit = Math.max(
    1,
    Math.min(all.length, height - lines.length - previewFloor),
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
      // Say which direction the rest is in, not just how much there is.
      const ordinals = shown
        .filter(
          (row): row is Extract<TableRow, { kind: "item" }> =>
            row.kind === "item",
        )
        .map((row) => row.ordinal);
      const above = ordinals.length === 0 ? 0 : Math.min(...ordinals);
      const below =
        ordinals.length === 0
          ? 0
          : Math.max(0, items.length - 1 - Math.max(...ordinals));
      const parts = [
        above > 0 ? `↑ ${above} above` : "",
        below > 0 ? `↓ ${below} below` : "",
      ].filter((part) => part !== "");
      lines.push(
        line(width, palette, [
          { text: `  ${parts.join("   ")}`, color: muted },
        ]),
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
  for (const previewLine of visible) {
    lines.push(
      Array.isArray(previewLine)
        ? panelLine(width, palette, previewLine)
        : panelRawLine(width, palette, previewLine.raw),
    );
  }
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
  lines.push(
    footerLine(width - 1, palette, searching, query, maxOffset > 0, view),
  );

  while (lines.length < height) lines.push(line(width, palette, []));
  return `${CLEAR}${frameLines(lines, height, width)}`;
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
    case "d":
      return "diff";
    case "\t":
      return "view";
    case "X":
      return "cleanup";
    case "a":
      return "assist";
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
  // The diff is a mode of this dashboard, not a separate program: `q` returns
  // to the list rather than closing the popup.
  // Which subtab is showing. The inbox and its workspaces are two datasets
  // behind one frame, so switching views swaps the data rather than the
  // program.
  let view: DashboardView = "reviews";
  let inbox = initial;
  let diffLines: string[] | null = null;
  let diffTitle = "";
  let diffOffset = 0;
  const input = process.stdin;
  const output = process.stdout;

  const visibleItems = (): DashboardItem[] =>
    rankDashboardItems(data.items, query).map((entry) => entry.item);

  const showView = async (next: DashboardView): Promise<void> => {
    if (next === view) return;
    if (next === "worktrees" && handlers.worktrees === undefined) return;
    if (view === "reviews") inbox = data;
    view = next;
    data = next === "worktrees" ? await handlers.worktrees!() : inbox;
    selectedIndex = 0;
    previewOffset = 0;
    query = "";
  };

  const render = (): void => {
    if (diffLines !== null) {
      output.write(
        renderDiffView(
          diffTitle,
          diffLines,
          diffOffset,
          loadPalette(),
          output.columns ?? 100,
          output.rows ?? 30,
        ),
      );
      return;
    }
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
        view,
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
        | "open"
        | "browser"
        | "acknowledge"
        | "refresh"
        | "diff"
        | "cleanup"
        | "assist"
      >,
    ): Promise<void> => {
      const item = visibleItems()[selectedIndex];
      if (action !== "refresh" && item === undefined) return;
      busy = true;
      try {
        if (action === "diff" && item !== undefined) {
          diffTitle = `${item.repository}${item.reference}  fetching diff…`;
          diffLines = [];
          diffOffset = 0;
          render();
          diffLines = await handlers.diff(item);
          diffTitle = `${item.repository}${item.reference}`;
        }
        if (action === "open" && item !== undefined && view === "worktrees") {
          if (handlers.focus) await handlers.focus(item);
          finish();
          return;
        }
        if (action === "open" && item !== undefined) {
          const close = await handlers.open(item);
          if (close) {
            finish();
            return;
          }
        }
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
        if (action === "assist" && item !== undefined && handlers.assist) {
          await handlers.assist(item);
          finish();
          return;
        }
        if (action === "cleanup" && item !== undefined && handlers.cleanup) {
          const refused = await handlers.cleanup(item);
          data =
            refused === null
              ? await handlers.worktrees!()
              : { ...data, status: refused };
          selectedIndex = Math.max(
            0,
            Math.min(selectedIndex, visibleItems().length - 1),
          );
        }
        if (action === "refresh") {
          data =
            view === "worktrees" && handlers.worktrees
              ? await handlers.worktrees()
              : await handlers.refresh();
          if (view === "reviews") inbox = data;
        }
      } catch (error) {
        data = errorData(data, error);
      } finally {
        busy = false;
        if (action !== "diff") previewOffset = 0;
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
      if (diffLines !== null) {
        const key = keyFor(text);
        if (text === "\u0003") {
          finish();
          return;
        }
        if (key === "quit" || key === "back") {
          diffLines = null;
          render();
          return;
        }
        if (key === "up") diffOffset = Math.max(0, diffOffset - 1);
        else if (key === "down") diffOffset += 1;
        else if (key === "scrollUp")
          diffOffset = Math.max(0, diffOffset - PREVIEW_SCROLL);
        else if (key === "scrollDown") diffOffset += PREVIEW_SCROLL;
        else if (key === "browser") {
          void runAction("browser");
          return;
        }
        render();
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
      if (key === "view") {
        void showView(view === "reviews" ? "worktrees" : "reviews").then(
          render,
        );
        return;
      }
      if (key === "back" || key === null) return;
      void runAction(key);
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
