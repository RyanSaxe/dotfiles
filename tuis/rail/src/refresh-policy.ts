// tmux uses the same control notifications for user focus movement and
// structural changes. Focus movement only changes which existing frame is
// person-facing; it does not justify invariant repair across every rail.
export type ControlRefreshKind = "full" | "navigation" | "ignore";

const NAVIGATION_EVENTS = new Set([
  "%client-session-changed",
  "%session-window-changed",
  "%window-pane-changed",
]);

const FULL_REFRESH_EVENTS = new Set([
  "%client-attached",
  "%client-detached",
  "%layout-change",
  "%pane-mode-changed",
  "%session-changed",
  "%session-renamed",
  "%sessions-changed",
  "%unlinked-window-add",
  "%unlinked-window-close",
  "%unlinked-window-renamed",
  "%window-add",
  "%window-close",
  "%window-renamed",
]);

export function controlRefreshKind(name: string): ControlRefreshKind {
  if (NAVIGATION_EVENTS.has(name)) return "navigation";
  if (FULL_REFRESH_EVENTS.has(name)) return "full";
  return "ignore";
}
