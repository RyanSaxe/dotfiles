import { blank, fmtElapsed, line } from "../cells.js";
import type { ReviewSnapshot } from "../attention/review.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import { pill, type RailRow } from "./rows.js";

function kindGlyph(kind: string): string {
  switch (kind) {
    case "ci":
      return "!";
    case "review_request":
      return "?";
    default:
      return "@";
  }
}

function kindColor(kind: string, palette: Palette): string {
  switch (kind) {
    case "ci":
      return palette.red;
    case "review_request":
      return palette.peach;
    default:
      return palette.mauve;
  }
}

function shortRepository(repository: string): string {
  const slash = repository.lastIndexOf("/");
  return slash >= 0 ? repository.slice(slash + 1) : repository;
}

function age(createdAt: string): string {
  const created = Date.parse(createdAt);
  if (!Number.isFinite(created)) return "?";
  return fmtElapsed(Math.max(0, (Date.now() - created) / 1000));
}

function summary(item: ReviewSnapshot["items"][number]): string {
  return item.summary.replace(/\s+/g, " ").trim();
}

export function reviewRows(
  snapshot: ReviewSnapshot,
  palette: Palette,
  width: number,
): RailRow[] {
  const bg = railBg(palette);
  const rows: RailRow[] = [];
  const pending = snapshot.unacknowledged;

  if (snapshot.lastError !== null && pending.length === 0) {
    rows.push({ text: blank(width, bg), item: false });
    rows.push({
      text: line(width, bg, [{ text: "observer error", fg: palette.red }]),
      item: true,
    });
    return rows;
  }

  if (pending.length === 0) {
    rows.push({ text: blank(width, bg), item: false });
    rows.push({
      text: line(width, bg, [
        { text: "Review clear", fg: blend(palette.green, bg, DIM_KEEP) },
      ]),
      item: true,
    });
    return rows;
  }

  for (const item of pending) {
    const color = kindColor(item.kind, palette);
    const chipBg = blend(palette.surface0, bg, DIM_KEEP);
    rows.push({ text: blank(width, bg), item: false });
    rows.push({
      text: line(
        width,
        bg,
        [
          ...pill(kindGlyph(item.kind), color, chipBg, bg),
          { text: " ", fg: palette.dim },
          {
            text: `${shortRepository(item.repository)}#${item.number}`,
            fg: item.priority === "high" ? palette.text : palette.lavender,
          },
          { text: " ", fg: palette.dim },
          { text: summary(item), fg: palette.dim },
        ],
        { text: age(item.createdAt), fg: blend(color, bg, DIM_KEEP) },
      ),
      item: true,
    });
  }
  return rows;
}
