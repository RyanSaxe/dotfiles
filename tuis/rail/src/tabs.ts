import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { XDG_STATE } from "./paths.js";

// Tabs are deliberately a small registry rather than a second rendering
// framework. A future Tasks implementation adds one definition and its row
// renderer beside the existing Agents and Review implementations.
export type RailTabId = "agents" | "review";

export interface RailTabDefinition {
  id: RailTabId;
  label: string;
  badge: string;
}

export const RAIL_TABS: readonly RailTabDefinition[] = [
  { id: "agents", label: "Agents", badge: "A" },
  { id: "review", label: "Review", badge: "R" },
];

export const RAIL_TAB_PATH = join(XDG_STATE, "dotfiles", "rail", "tab");

function isRailTabId(value: string): value is RailTabId {
  return RAIL_TABS.some((tab) => tab.id === value);
}

export function loadRailTab(path = RAIL_TAB_PATH): RailTabId {
  try {
    const value = readFileSync(path, "utf8").trim();
    return isRailTabId(value) ? value : "agents";
  } catch {
    return "agents";
  }
}

export function saveRailTab(tab: RailTabId, path = RAIL_TAB_PATH): void {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, `${tab}\n`);
}
