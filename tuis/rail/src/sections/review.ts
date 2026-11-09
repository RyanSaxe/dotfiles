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
  if (item.reasons.some((reason) => reason.kind === "ci")) return palette.red;
  return item.targetKind === "issue" ? palette.mauve : palette.peach;
}

function shortRepository(repository: string): string {
  const slash = repository.lastIndexOf("/");
  return slash >= 0 ? repository.slice(slash + 1) : repository;
}

// `repository#number` is the identity, and the number is the part that
// actually identifies it. Clipping the whole token from the right removes the
// number first — `buffergolf.nvim#…` says almost nothing. Shorten the
// repository instead and keep the number whole.
function identityLabel(
  repository: string,
  number: number,
  budget: number,
): string {
  const name = shortRepository(repository);
  const suffix = `#${number}`;
  const full = `${name}${suffix}`;
  if (full.length <= budget) return full;
  const room = budget - suffix.length - 1;
  if (room < 1) return suffix.slice(0, Math.max(1, budget));
  return `${name.slice(0, room)}…${suffix}`;
}

function age(createdAt: string): string {
  const created = Date.parse(createdAt);
  if (!Number.isFinite(created)) return "?";
  return fmtElapsed(Math.max(0, (Date.now() - created) / 1000));
}

function summary(item: ReviewSnapshot["items"][number]): string {
  return item.reasons
    .map((reason) => reason.summary.replace(/\s+/g, " ").trim())
    .join(" · ");
}

function latestActivity(item: ReviewSnapshot["items"][number]): string {
  return item.reasons.reduce(
    (latest, reason) => (reason.createdAt > latest ? reason.createdAt : latest),
    item.reasons[0]?.createdAt ?? "",
  );
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
    const elapsed = age(latestActivity(item));
    // The pill is three cells, then a space; the timer sits flush right with
    // a cell of air. Whatever is left is the identity's, and the summary gets
    // only what the identity does not need.
    const budget = Math.max(1, width - 4 - elapsed.length - 1);
    const identity = identityLabel(item.repository, item.number, budget);
    const remaining = budget - identity.length - 1;
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          // The review number is the same quiet jump pill used for an
          // elsewhere agent — numbered pills stay neutral everywhere.
          ...pill(number, blend(palette.dim2, bg, DIM_KEEP), chipBg, bg),
          { text: " ", fg: dim },
          { text: identity, fg: identityFg },
          ...(remaining > 1 ? [{ text: ` ${summary(item)}`, fg: dim }] : []),
        ],
        { text: elapsed, fg: dim },
      ),
    );
  }
  return rows;
}
