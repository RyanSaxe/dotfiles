import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { run } from "./data.js";
import { openReviewItem } from "./review-dashboard.js";
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
    case "task_complete":
      throw new Error(
        "task elements are not available until the Obsidian task source is implemented",
      );
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
