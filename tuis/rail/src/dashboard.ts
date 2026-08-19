import { loadPalette, bg, fg, RESET, blend, type Palette } from "./theme.js";
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

function borderColor(palette: Palette): string {
  return blend(palette.lavender, background(palette), 0.58);
}

function mutedColor(palette: Palette): string {
  return blend(palette.dim, background(palette), 0.72);
}

function attentionColor(
  item: DashboardItem,
  palette: Palette,
  selected: boolean,
): string {
  if (selected) return palette.text;
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

function rule(
  width: number,
  palette: Palette,
  kind: "top" | "middle" | "bottom",
  title?: string,
): string {
  const left = kind === "top" ? "╭" : kind === "bottom" ? "╰" : "├";
  const right = kind === "top" ? "╮" : kind === "bottom" ? "╯" : "┤";
  const inner = width - 2;
  const label = title === undefined ? "" : ` ${title} `;
  const fill = Math.max(0, inner - widthOf(label));
  return `${fg(borderColor(palette))}${left}${label}${"─".repeat(fill)}${right}${RESET}`;
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

function row(
  width: number,
  palette: Palette,
  cells: Cell[],
  selected = false,
): string {
  const lineBackground = selected
    ? blend(palette.surface0, background(palette), 0.9)
    : background(palette);
  return `${fg(borderColor(palette))}│${content(width - 2, palette, cells, lineBackground)}${fg(borderColor(palette))}│${RESET}`;
}

function rightAlignedRow(
  width: number,
  palette: Palette,
  left: Cell[],
  rightText: string,
): string {
  const inner = width - 2;
  const rightWidth = widthOf(rightText);
  const leftWidth = Math.max(0, inner - rightWidth - 1);
  return row(width, palette, [
    {
      text: padded(left.map((cell) => cell.text).join(""), leftWidth),
      color: left[0]?.color,
    },
    { text: " ", color: background(palette) },
    { text: rightText, color: mutedColor(palette) },
  ]);
}

function tableWidths(inner: number): number[] {
  const fixed = [3, 18, 8, 11, 12, 8];
  const separators = 6;
  const title = Math.max(
    8,
    inner - separators - fixed.reduce((sum, width) => sum + width, 0),
  );
  return [...fixed, title];
}

function tableCells(
  values: string[],
  widths: number[],
  colors: string[],
): Cell[] {
  const cells: Cell[] = [];
  values.forEach((value, index) => {
    if (index > 0) cells.push({ text: "│", color: colors[index] });
    cells.push({
      text: padded(value, widths[index] ?? 0),
      color: colors[index] ?? colors[0],
    });
  });
  return cells;
}

function tableHeader(width: number, palette: Palette): string {
  const widths = tableWidths(width - 2);
  return row(
    width,
    palette,
    tableCells(
      ["#", "Project", "Ref", "Kind", "State", "Time", "Title"],
      widths,
      Array.from({ length: widths.length }, () => mutedColor(palette)),
    ),
  );
}

function tableItem(
  width: number,
  palette: Palette,
  item: DashboardItem,
  index: number,
  selected: boolean,
): string {
  const widths = tableWidths(width - 2);
  const tone = attentionColor(item, palette, selected);
  const neutral = selected ? palette.text : mutedColor(palette);
  return row(
    width,
    palette,
    tableCells(
      [
        String(index + 1),
        item.project,
        item.reference,
        item.kind,
        item.state,
        item.time,
        item.title,
      ],
      widths,
      [neutral, neutral, neutral, neutral, tone, tone, tone],
    ),
    selected,
  );
}

function emptyTableRow(width: number, palette: Palette, text: string): string {
  const widths = tableWidths(width - 2);
  return row(
    width,
    palette,
    tableCells(
      ["", "", "", "", "", "", text],
      widths,
      Array.from({ length: widths.length }, () => mutedColor(palette)),
    ),
  );
}

function previewLines(
  data: DashboardData,
  selected: DashboardItem | undefined,
  palette: Palette,
): Cell[][] {
  if (selected === undefined) {
    return [
      [{ text: data.emptyMessage, color: mutedColor(palette) }],
      [{ text: data.status, color: mutedColor(palette) }],
      [{ text: "", color: palette.text }],
      [{ text: "", color: palette.text }],
    ];
  }

  const tone = attentionColor(selected, palette, false);
  const lines: Cell[][] = [
    [
      {
        text: `${selected.project}${selected.reference} · ${selected.kind}`,
        color: tone,
      },
    ],
    [{ text: selected.title, color: palette.text }],
    [{ text: selected.preview, color: mutedColor(palette) }],
    [
      {
        text: selected.url ?? "",
        color: blend(palette.lavender, background(palette), 0.75),
      },
    ],
  ];
  if (data.error !== null) {
    lines[3] = [{ text: data.error, color: palette.red }];
  }
  return lines;
}

export function renderDashboard(
  data: DashboardData,
  selectedIndex: number,
  palette: Palette,
  columns: number,
  rows: number,
): string {
  const width = Math.max(64, columns);
  const height = Math.max(16, rows);
  const items = data.items;
  const selected = items[selectedIndex];
  const tableLimit = Math.max(
    1,
    Math.min(items.length || 1, Math.floor((height - 15) / 3)),
  );
  const tableStart =
    items.length === 0
      ? 0
      : Math.min(
          Math.max(0, selectedIndex - tableLimit + 1),
          Math.max(0, items.length - tableLimit),
        );
  const tableEnd = tableStart + tableLimit;
  const shown = items.slice(tableStart, tableEnd);
  const lines: string[] = [
    rule(width, palette, "top"),
    rightAlignedRow(
      width,
      palette,
      [
        { text: "Rail dashboard   ", color: palette.text },
        { text: surfaceLabel(data.surface), color: palette.accent },
      ],
      data.status,
    ),
    rule(width, palette, "middle"),
    row(width, palette, [
      {
        text: padded("Reviews", 10),
        color:
          data.surface === "reviews" ? palette.accent : mutedColor(palette),
      },
      { text: "  ", color: mutedColor(palette) },
      {
        text: "Tasks",
        color: data.surface === "tasks" ? palette.accent : mutedColor(palette),
      },
    ]),
    rule(width, palette, "middle"),
    tableHeader(width, palette),
    rule(width, palette, "middle"),
  ];

  if (shown.length === 0) {
    lines.push(emptyTableRow(width, palette, data.emptyMessage));
  } else {
    shown.forEach((item, offset) => {
      const index = tableStart + offset;
      lines.push(
        tableItem(width, palette, item, index, index === selectedIndex),
      );
    });
    if (tableStart > 0 || tableEnd < items.length) {
      lines.push(
        row(width, palette, [
          {
            text: `… ${tableStart} earlier · ${Math.max(0, items.length - tableEnd)} later`,
            color: mutedColor(palette),
          },
        ]),
      );
    }
  }

  const selectedLines = previewLines(data, selected, palette);
  const fixedAfterTable = 1 + 1 + selectedLines.length + 1 + 1 + 1;
  const previewFill = Math.max(0, height - lines.length - fixedAfterTable);
  lines.push(rule(width, palette, "middle", "Preview"));
  lines.push(
    row(width, palette, [
      {
        text: selected?.title ?? surfaceLabel(data.surface),
        color: palette.text,
      },
    ]),
  );
  for (const previewLine of selectedLines)
    lines.push(row(width, palette, previewLine));
  for (let index = 0; index < previewFill; index += 1) {
    lines.push(row(width, palette, []));
  }
  lines.push(rule(width, palette, "middle"));
  lines.push(
    row(width, palette, [
      {
        text: "↑/↓ j/k Navigate   Enter Open   Ctrl-d Acknowledge   r Refresh   q/Esc Close",
        color: mutedColor(palette),
      },
    ]),
  );
  lines.push(rule(width, palette, "bottom"));

  while (lines.length < height)
    lines.splice(lines.length - 3, 0, row(width, palette, []));
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
  const input = process.stdin;
  const output = process.stdout;

  const render = (): void => {
    const maxIndex = Math.max(0, data.items.length - 1);
    selectedIndex = Math.min(selectedIndex, maxIndex);
    output.write(
      renderDashboard(
        data,
        selectedIndex,
        loadPalette(),
        output.columns ?? 100,
        output.rows ?? 30,
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
      const item = data.items[selectedIndex];
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

    const onData = (chunk: string | Buffer): void => {
      if (busy) return;
      const key = keyFor(
        typeof chunk === "string" ? chunk : chunk.toString("utf8"),
      );
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
          Math.max(0, data.items.length - 1),
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
