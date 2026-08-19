import { fmtElapsed } from "../cells.js";
import type { ReviewSnapshot } from "../attention/review.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import {
  attentionTextColor,
  pill,
  spacedItem,
  type AttentionTone,
  type RailRow,
} from "./rows.js";

function kindTone(kind: string): AttentionTone {
  switch (kind) {
    case "ci":
      return "error";
    default:
      return "waiting";
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
    rows.push(
      ...spacedItem(width, bg, [{ text: "observer error", fg: palette.red }]),
    );
    return rows;
  }

  if (pending.length === 0) {
    rows.push(
      ...spacedItem(width, bg, [
        { text: "Review clear", fg: blend(palette.green, bg, DIM_KEEP) },
      ]),
    );
    return rows;
  }

  for (const item of pending) {
    const tone = kindTone(item.kind);
    const chipBg = blend(palette.surface0, bg, DIM_KEEP);
    const dim = blend(palette.dim, bg, DIM_KEEP);
    const number = String(rows.filter((row) => row.item).length + 1);
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          // The review number is the same quiet jump pill used for an
          // elsewhere agent. Its attention lives in the primary text/time.
          ...pill(number, blend(palette.dim2, bg, DIM_KEEP), chipBg, bg),
          { text: " ", fg: dim },
          {
            text: `${shortRepository(item.repository)}#${item.number} `,
            fg: dim,
          },
          { text: summary(item), fg: attentionTextColor(tone, palette) },
        ],
        { text: age(item.createdAt), fg: attentionTextColor(tone, palette) },
      ),
    );
  }
  return rows;
}
