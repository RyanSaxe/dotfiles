import { fmtElapsed } from "../cells.js";
import type { ReviewSnapshot } from "../attention/review.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import { pill, spacedItem, type RailRow } from "./rows.js";

// Hue follows the object, matching the dashboard: red CI, peach
// pull-request activity, mauve issue activity.
function itemColor(
  item: ReviewSnapshot["items"][number],
  palette: Palette,
): string {
  if (item.kind === "ci") return palette.red;
  return item.targetKind === "issue" ? palette.mauve : palette.peach;
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
    const chipBg = blend(palette.surface0, bg, DIM_KEEP);
    const dim = blend(palette.dim, bg, DIM_KEEP);
    const number = String(rows.filter((row) => row.item).length + 1);
    // Attention colour sits on `repository#number` — the first stable token
    // after the jump pill, and the one guaranteed to survive truncation at
    // rail width. Summary and age are supporting text and stay dim, so a
    // clipped summary can never take the signal with it.
    const identityFg = blend(itemColor(item, palette), bg, DIM_KEEP);
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          // The review number is the same quiet jump pill used for an
          // elsewhere agent — numbered pills stay neutral everywhere.
          ...pill(number, blend(palette.dim2, bg, DIM_KEEP), chipBg, bg),
          { text: " ", fg: dim },
          {
            text: `${shortRepository(item.repository)}#${item.number} `,
            fg: identityFg,
          },
          { text: summary(item), fg: dim },
        ],
        { text: age(item.createdAt), fg: dim },
      ),
    );
  }
  return rows;
}
