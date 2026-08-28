import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import type { AgentStatus, StableAgentState } from "./data.js";
import { XDG_STATE } from "./paths.js";

export const STABILITY_PATH = join(
  XDG_STATE,
  "dotfiles/rail/status-stability.json",
);

const STATUSES: ReadonlySet<string> = new Set(["working", "waiting", "done"]);

export function loadStableStatuses(): Map<string, StableAgentState> {
  try {
    const parsed = JSON.parse(readFileSync(STABILITY_PATH, "utf8")) as Record<
      string,
      Partial<StableAgentState>
    >;
    return new Map(
      Object.entries(parsed).flatMap(([paneId, state]) =>
        STATUSES.has(state.status ?? "") && typeof state.statusTs === "number"
          ? [
              [
                paneId,
                {
                  status: state.status as AgentStatus,
                  statusTs: state.statusTs,
                },
              ] as const,
            ]
          : [],
      ),
    );
  } catch {
    return new Map();
  }
}

export function stableStatusesKey(
  statuses: Map<string, StableAgentState>,
): string {
  return JSON.stringify(
    [...statuses.entries()].sort(([a], [b]) => a.localeCompare(b)),
  );
}

export function saveStableStatuses(
  statuses: Map<string, StableAgentState>,
): void {
  mkdirSync(dirname(STABILITY_PATH), { recursive: true });
  const temp = `${STABILITY_PATH}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(Object.fromEntries(statuses.entries())));
  renameSync(temp, STABILITY_PATH);
}
