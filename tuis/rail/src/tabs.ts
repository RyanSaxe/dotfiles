import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { XDG_STATE } from "./paths.js";

// Tabs are deliberately a small registry rather than a second rendering
// framework. Each tab owns the action for its numbered elements; the tmux
// key table only supplies the number and never needs to know what it means.
export type RailTabId = "agents" | "reviews" | "tasks";

export type RailElementAction = "agent_jump" | "review_open" | "task_jump";

export type RailTabAttention = Readonly<Record<RailTabId, boolean>>;

export interface RailTabDefinition {
  id: RailTabId;
  label: string;
  badge: string;
  elementAction: RailElementAction;
}

export const RAIL_TABS: readonly RailTabDefinition[] = [
  {
    id: "agents",
    label: "Agents",
    badge: "A",
    elementAction: "agent_jump",
  },
  {
    id: "reviews",
    label: "Reviews",
    badge: "R",
    elementAction: "review_open",
  },
  {
    id: "tasks",
    label: "Tasks",
    badge: "T",
    elementAction: "task_jump",
  },
];

export const RAIL_TAB_PATH = join(XDG_STATE, "dotfiles", "rail", "tab");

function normalizeRailTabId(value: string): RailTabId | null {
  if (value === "review") return "reviews";
  return RAIL_TABS.find((tab) => tab.id === value)?.id ?? null;
}

export function loadRailTab(path = RAIL_TAB_PATH): RailTabId {
  try {
    const value = readFileSync(path, "utf8").trim();
    return normalizeRailTabId(value) ?? "agents";
  } catch {
    return "agents";
  }
}

export function saveRailTab(tab: RailTabId, path = RAIL_TAB_PATH): void {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, `${tab}\n`);
}
