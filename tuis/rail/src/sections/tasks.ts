import {
  railTasks,
  shortDue,
  type TaskSnapshot,
  type TaskState,
} from "../tasks.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import { pill, spacedItem, type RailRow } from "./rows.js";

// Hue follows the due state, matching the dashboard: overdue red, today
// peach, tomorrow yellow. Today and tomorrow are the two states a glance has
// to separate, so they never share a hue.
function dueColor(state: TaskState, palette: Palette): string {
  switch (state) {
    case "overdue":
      return palette.red;
    case "today":
      return palette.peach;
    case "tomorrow":
      return palette.yellow;
    // Only the three rail states reach a row; near, later and undated tasks
    // are filtered out before this. The dashboard's near-term mauve is the
    // fallback so an unfiltered row would still read as a due date.
    default:
      return palette.mauve;
  }
}

// The right span is the row's timer slot: a date where the date is the
// news, and the word where it is not. `2026-08-22` says nothing to someone
// who only needs to know the task is today's.
function dueSpan(state: TaskState, due: string | null, dim: string) {
  if (state === "today") return { text: "today", fg: dim };
  if (state === "tomorrow") return { text: "tmr", fg: dim };
  return { text: shortDue(due), fg: dim };
}

// The rail shows only what today needs: incomplete tasks that are overdue,
// due today, or due tomorrow. Everything further out lives in the dashboard.
//
// A task row IS an agent row: numbered jump pill, an identity token colored
// by state, and a right-aligned span of supporting text. alt+space then the
// digit opens the note at the task's line — urgency lives in the hue and
// the order, never in a label of its own.
export function taskRows(
  snapshot: TaskSnapshot,
  palette: Palette,
  width: number,
): RailRow[] {
  const bg = railBg(palette);
  const dim = blend(palette.dim, bg, DIM_KEEP);

  if (snapshot.error !== null) {
    // The CLI's own sentence, dimmed. A vault this machine does not have is
    // not an attention event, and red belongs to overdue work.
    return spacedItem(width, bg, [{ text: snapshot.error, fg: dim }]);
  }

  const tasks = railTasks(snapshot.tasks);
  if (tasks.length === 0) {
    return spacedItem(width, bg, [
      { text: "Nothing due", fg: blend(palette.green, bg, DIM_KEEP) },
    ]);
  }

  const dim2 = blend(palette.dim2, bg, DIM_KEEP);
  const chipBg = blend(palette.surface0, bg, DIM_KEEP);
  const rows: RailRow[] = [];
  for (const [index, task] of tasks.entries()) {
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          // Every row is numbered, the way every pending review is. The tmux
          // element table binds 1-9, so a pill past the ninth is a position
          // rather than a keystroke — but a list that stops counting reads as
          // a list that stopped. The tenth pill costs a cell of the task's
          // text and nothing else: `line` gives the due span its width first,
          // so it still lands flush right.
          ...pill(String(index + 1), dim2, chipBg, bg),
          { text: " ", fg: dim },
          {
            text: task.text,
            fg: blend(dueColor(task.state, palette), bg, DIM_KEEP),
          },
        ],
        dueSpan(task.state, task.due, dim),
      ),
    );
  }
  return rows;
}
