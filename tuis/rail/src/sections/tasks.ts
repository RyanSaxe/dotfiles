import { blank, line } from "../cells.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import type { RailRow } from "./rows.js";

// The Tasks tab is intentionally a real surface before its source exists.
// It reserves the row shape and tab routing without inventing task data or
// pretending that an empty task list is the completed task implementation.
export function taskRows(palette: Palette, width: number): RailRow[] {
  const bg = railBg(palette);
  return [
    { text: blank(width, bg), item: false },
    {
      text: line(width, bg, [
        {
          text: "Tasks pending Obsidian integration",
          fg: blend(palette.dim, bg, DIM_KEEP),
        },
      ]),
      item: false,
    },
  ];
}
