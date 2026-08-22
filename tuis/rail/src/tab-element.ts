import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { run } from "./data.js";
import { openReviewItem, openTaskElement } from "./review-dashboard.js";
import { XDG_STATE } from "./paths.js";
import { RAIL_TABS, loadRailTab } from "./tabs.js";

const HINTS_PATH = join(XDG_STATE, "dotfiles", "rail", "hints.tsv");

async function jumpAgent(number: string): Promise<void> {
  const { stdout } = await run("tmux", [
    "display-message",
    "-p",
    "#{session_name}",
  ]);
  const viewingSession = stdout.trim();
  const row = readFileSync(HINTS_PATH, "utf8")
    .split("\n")
    .map((line) => line.split("\t"))
    .find((fields) => fields[0] === viewingSession && fields[1] === number);
  const targetSession = row?.[2];
  const targetPane = row?.[3];
  if (targetSession === undefined || targetPane === undefined) {
    throw new Error(`no agent element ${number}`);
  }
  await run(join(homedir(), ".config/tmux/scripts/goto-pane.sh"), [
    targetSession,
    targetPane,
    targetPane,
  ]);
}

async function main(): Promise<void> {
  const rawNumber = process.argv[2] ?? "";
  const number = Number.parseInt(rawNumber, 10);
  if (!Number.isInteger(number) || number < 1 || number > 9) {
    throw new Error("usage: tab-element <number 1-9>");
  }

  const activeTab = loadRailTab();
  const definition = RAIL_TABS.find((tab) => tab.id === activeTab);
  if (definition === undefined)
    throw new Error(`unknown rail tab: ${activeTab}`);

  switch (definition.elementAction) {
    case "agent_jump":
      await jumpAgent(String(number));
      return;
    case "review_open":
      if (!(await openReviewItem(number - 1))) {
        throw new Error(`no review element ${number}`);
      }
      return;
    case "task_jump":
      // A jump, never a completion: ids are recomputed on every read, so the
      // Nth row of a frame that may be a refresh old is not something a
      // destructive action may be aimed at. Opening the note is safe when
      // the row has moved — you land on the task and can see it. Completing
      // happens in the dashboard (alt+T), against the row you have selected.
      if (!(await openTaskElement(number - 1))) {
        throw new Error(`no task element ${number}`);
      }
      return;
  }
}

// tmux shows ANY output or non-zero exit of a `run-shell` binding in a
// view-mode overlay: the window is renamed `[tmux]` (the rail's own window
// row says so) and the overlay sits there until you press q. A keystroke
// that found nothing is not worth a modal — say it in the status line the
// way every other tmux miss is said, and exit clean.
main().catch(async (error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  await run("tmux", ["display-message", `rail: ${message}`]).catch(() => {});
});
