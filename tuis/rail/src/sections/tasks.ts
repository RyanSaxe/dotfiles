import { blank, line } from "../cells.js";
import {
  railTasks,
  shortDue,
  type TaskSnapshot,
  type TaskState,
} from "../tasks.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import { spacedItem, type RailRow } from "./rows.js";

// Hue follows the due state, matching the dashboard: overdue red, today and
// tomorrow peach, near-term mauve.
function dueColor(state: TaskState, palette: Palette): string {
  switch (state) {
    case "overdue":
      return palette.red;
    case "today":
    case "tomorrow":
      return palette.peach;
    // Only the four rail states reach a row — later and undated tasks are
    // filtered out before this.
    default:
      return palette.mauve;
  }
}

// The date earns its cells only where it says something the group label has
// not: how late, or which day this week. Under "today" and "tomorrow" it is
// the label again, so the row gives the text those cells instead — the same
// way a window row carries a timer only when there is an agent behind it.
function dueSpan(state: TaskState, due: string | null, dim: string) {
  if (state === "today" || state === "tomorrow") return undefined;
  return { text: shortDue(due), fg: dim };
}

// The rail shows only what the week needs: incomplete tasks that are
// overdue, due today or tomorrow, or due inside the next seven days.
//
// A dim state label heads each group and the rows sit under it at the
// section's usual text column — tasks have no jump target, so the pill's
// three cells stay empty exactly as they do for an elsewhere agent with no
// hint. Colour carries urgency; the label carries it in text.
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

  const rows: RailRow[] = [];
  let group: TaskState | null = null;
  for (const task of tasks) {
    if (task.state !== group) {
      group = task.state;
      rows.push({ text: blank(width, bg), item: false });
      rows.push({
        text: line(width, bg, [{ text: task.state, fg: dim }]),
        item: false,
      });
    }
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          { text: "   ", fg: dim },
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
