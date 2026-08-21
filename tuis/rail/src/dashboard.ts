import { rank, type Ranked } from "./search.js";
import { bg, blend, fg, loadPalette, RESET, type Palette } from "./theme.js";
import type { AttentionTone } from "./sections/rows.js";

export type DashboardSurface = "reviews" | "tasks";

export interface DashboardItem {
  id: string;
  project: string;
  reference: string;
  kind: string;
  state: string;
  time: string;
  title: string;
  preview: string;
  details?: readonly string[];
  url: string | null;
  tone: AttentionTone;
  acknowledged: boolean;
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
  acknowledge(item: DashboardItem): Promise<void>;
}

type DashboardKey =
  "up" | "down" | "open" | "acknowledge" | "refresh" | "quit" | null;

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

function attentionColor(item: DashboardItem, palette: Palette): string {
  if (item.acknowledged) return mutedColor(palette);
  switch (item.tone) {
    case "working":
      return palette.statusWorking;
    case "waiting":
      return palette.statusWaiting;
    case "done":
      return palette.statusDone;
    case "error":
      return palette.red;
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

function panelLine(width: number, palette: Palette, cells: Cell[]): string {
  return line(width, palette, [
    { text: "│", color: ruleColor(palette) },
    ...cells,
    { text: "│", color: ruleColor(palette) },
  ]);
}

function tableWidths(width: number): number[] {
  const gap = 2;
  const fixed = [4, 23, 9, 12, 14, 9];
  const title = Math.max(
    12,
    width - gap * 6 - fixed.reduce((sum, value) => sum + value, 0),
  );
  return [...fixed, title];
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
      ["#", "Project", "Ref", "Kind", "State", "Time", "Title"],
      widths,
      Array.from({ length: widths.length }, () => palette.text),
      muted,
    ),
  );
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
  const tone = attentionColor(item, palette);
  const neutral = selected ? palette.text : mutedColor(palette);
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
        item.project,
        item.reference,
        item.kind,
        item.state,
        item.time,
        item.title,
      ],
      widths,
      [
        selected ? palette.accent : neutral,
        neutral,
        neutral,
        neutral,
        tone,
        tone,
        selected ? palette.text : tone,
      ],
      neutral,
      {
        color: palette.notify,
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
  const widths = tableWidths(width);
  const muted = mutedColor(palette);
  return line(
    width,
    palette,
    tableCells(
      ["", text, "", "", "", "", ""],
      widths,
      Array.from({ length: widths.length }, () => muted),
      muted,
    ),
  );
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

function previewLines(
  data: DashboardData,
  selected: DashboardItem | undefined,
  palette: Palette,
  query: string,
  width: number,
): Cell[][] {
  if (selected === undefined) {
    return [
      [
        {
          text: query === "" ? data.emptyMessage : `No matches for /${query}`,
          color: mutedColor(palette),
        },
      ],
      [{ text: data.status, color: mutedColor(palette) }],
      [{ text: "", color: palette.text }],
    ];
  }

  const tone = attentionColor(selected, palette);
  const lines: Cell[][] = [
    [{ text: selected.title, color: palette.text }],
    [
      {
        text: `${selected.project}${selected.reference} · ${selected.kind} · ${selected.state}`,
        color: tone,
      },
    ],
    [{ text: selected.preview, color: mutedColor(palette) }],
  ];
  const detailWidth = Math.max(1, width - 4);
  for (const detail of selected.details ?? []) {
    for (const wrapped of wrapText(detail, detailWidth)) {
      lines.push([{ text: wrapped, color: mutedColor(palette) }]);
    }
  }
  return lines;
}

function footerLine(
  width: number,
  palette: Palette,
  searching: boolean,
  query: string,
): string {
  if (searching) {
    return line(width, palette, [
      { text: `/${query}▌`, color: palette.accent },
      {
        text: "   Enter Apply   Esc Cancel   Backspace Delete",
        color: mutedColor(palette),
      },
    ]);
  }
  return line(width, palette, [
    { text: "/", color: palette.accent },
    { text: " Search   ", color: palette.text },
    { text: "↑↓ j/k", color: palette.text },
    { text: " Navigate   ", color: mutedColor(palette) },
    { text: "Enter", color: palette.text },
    { text: " Open   ", color: mutedColor(palette) },
    { text: "Ctrl-d", color: palette.text },
    { text: " Acknowledge   ", color: mutedColor(palette) },
    { text: "r", color: palette.text },
    { text: " Refresh   ", color: mutedColor(palette) },
    { text: "q", color: palette.text },
    { text: " Quit", color: mutedColor(palette) },
  ]);
}

// The columns the table actually shows, in cell order. The PR/issue body is
// deliberately absent: it is what made every query match, and highlighting a
// match you cannot see is worse than not matching at all.
function searchFields(item: DashboardItem): string[] {
  return [
    item.project,
    item.reference,
    item.kind,
    item.state,
    item.time,
    item.title,
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
): string {
  const width = Math.max(64, columns);
  const height = Math.max(16, rows);
  const ranked = rankDashboardItems(data.items, query);
  const items = ranked.map((entry) => entry.item);
  const selected = items[selectedIndex];
  const status =
    query.trim() === ""
      ? data.status
      : `${items.length}/${data.items.length} matches`;
  const tableLimit = Math.max(
    1,
    Math.min(items.length || 1, Math.floor((height - 10) / 2)),
  );
  const tableStart =
    items.length === 0
      ? 0
      : Math.min(
          Math.max(0, selectedIndex - tableLimit + 1),
          Math.max(0, items.length - tableLimit),
        );
  const tableEnd = tableStart + tableLimit;
  const shown = ranked.slice(tableStart, tableEnd);
  const lines: string[] = [
    rightAlignedLine(
      width,
      palette,
      [
        { text: "  ", color: palette.text },
        {
          text: surfaceLabel(data.surface),
          color:
            data.surface === "reviews" ? palette.accent : mutedColor(palette),
        },
        { text: "  |  ", color: mutedColor(palette) },
        {
          text: "Tasks",
          color:
            data.surface === "tasks" ? palette.accent : mutedColor(palette),
        },
      ],
      query.trim() === "" ? status : `/${query} · ${status}`,
    ),
    rule(width, palette),
    tableHeader(width, palette),
  ];

  if (shown.length === 0) {
    lines.push(
      emptyTableRow(
        width,
        palette,
        query === "" ? data.emptyMessage : "No matching items",
      ),
    );
  } else {
    shown.forEach((entry, offset) => {
      const index = tableStart + offset;
      lines.push(
        tableItem(
          width,
          palette,
          entry.item,
          index,
          index === selectedIndex,
          entry.hits,
        ),
      );
    });
    if (tableStart > 0 || tableEnd < items.length) {
      lines.push(
        line(width, palette, [
          {
            text: `  … ${tableStart} earlier · ${Math.max(0, items.length - tableEnd)} later`,
            color: mutedColor(palette),
          },
        ]),
      );
    }
  }

  const selectedLines = previewLines(data, selected, palette, query, width);
  const fixedAfterTable = 1 + selectedLines.length + 1 + 1;
  const previewFill = Math.max(0, height - lines.length - fixedAfterTable);
  const previewTitle = selected
    ? `Preview: ${selected.project}${selected.reference}`
    : `Preview: ${surfaceLabel(data.surface)}`;
  lines.push(panelRule(width, palette, "top", previewTitle));
  for (const previewLine of selectedLines)
    lines.push(panelLine(width, palette, previewLine));
  for (let index = 0; index < previewFill; index += 1)
    lines.push(panelLine(width, palette, []));
  lines.push(panelRule(width, palette, "bottom"));
  lines.push(footerLine(width, palette, searching, query));

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
    case "\u0004":
      return "acknowledge";
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
      action: Exclude<DashboardKey, "up" | "down" | "quit" | null>,
    ): Promise<void> => {
      const item = visibleItems()[selectedIndex];
      if ((action === "open" || action === "acknowledge") && item === undefined)
        return;
      busy = true;
      try {
        if (action === "open" && item !== undefined) await handlers.open(item);
        if (action === "acknowledge" && item !== undefined) {
          await handlers.acknowledge(item);
          data = await handlers.refresh();
        }
        if (action === "refresh") data = await handlers.refresh();
      } catch (error) {
        data = errorData(data, error);
      } finally {
        busy = false;
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
        render();
        return;
      }
      if (key === "down") {
        selectedIndex = Math.min(
          Math.max(0, visibleItems().length - 1),
          selectedIndex + 1,
        );
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
