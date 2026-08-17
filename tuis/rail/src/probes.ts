// Host-level probes, collected once per tick. The decisions they feed are
// pure functions of the probed values so the routing logic stays testable
// without a macOS session behind it.

import { platform } from "node:os";

import { run } from "./data.js";

// No system input for this long means nobody is at the desk and the phone
// is the channel. Tunable.
export const PRESENCE_IDLE_SECS = 120;

// Same terminals the client termname detection in data.ts recognizes —
// the apps whose OS focus means the rail is actually on screen.
const TERMINAL_APP = /ghostty|kitty/i;

export interface HostFacts {
  // Seconds since the last keyboard/mouse input; null when unprobeable.
  inputIdleSecs: number | null;
  // Frontmost application name; null when unprobeable.
  focusedApp: string | null;
}

// HIDIdleTime is reported in nanoseconds.
const HID_IDLE = /"HIDIdleTime"\s*=\s*(\d+)/;
// The probe spawns a process and parses a registry subtree, and it feeds a
// minutes-wide threshold — riding the 250ms render cadence would be pure
// waste. Time-gated rather than tick-gated so the daemon's idle back-off
// can't stretch it further.
const INPUT_IDLE_PROBE_MS = 5000;
let inputIdleCache: { at: number; secs: number | null } | null = null;

async function probeInputIdle(): Promise<number | null> {
  const now = Date.now();
  if (inputIdleCache && now - inputIdleCache.at < INPUT_IDLE_PROBE_MS) {
    return inputIdleCache.secs;
  }
  let secs: number | null = null;
  try {
    // -r -d 1 -k narrows the dump to the one node's one key: ~4KB instead
    // of the ~300KB a bare class dump costs.
    const { stdout } = await run("ioreg", [
      "-r",
      "-c",
      "IOHIDSystem",
      "-k",
      "HIDIdleTime",
      "-d",
      "1",
    ]);
    const match = HID_IDLE.exec(stdout);
    secs = match ? Number(match[1]) / 1e9 : null;
  } catch {
    // ioreg missing or failed: no presence signal from this probe.
  }
  inputIdleCache = { at: now, secs };
  return secs;
}

async function probeFocusedApp(): Promise<string | null> {
  try {
    const { stdout } = await run("aerospace", [
      "list-windows",
      "--focused",
      "--format",
      "%{app-name}",
    ]);
    const name = stdout.trim();
    if (name) return name;
  } catch {
    // aerospace missing or not running; lsappinfo answers the same question.
  }
  try {
    const { stdout: front } = await run("lsappinfo", ["front"]);
    const { stdout } = await run("lsappinfo", [
      "info",
      "-only",
      "LSDisplayName",
      front.trim(),
    ]);
    return /"LSDisplayName"="(.+)"/.exec(stdout)?.[1] ?? null;
  } catch {
    return null;
  }
}

export async function collectHostFacts(): Promise<HostFacts> {
  if (platform() !== "darwin") {
    return { inputIdleSecs: null, focusedApp: null };
  }
  const [inputIdleSecs, focusedApp] = await Promise.all([
    probeInputIdle(),
    probeFocusedApp(),
  ]);
  return { inputIdleSecs, focusedApp };
}

// Present = someone is at this machine. System input idle is the truth on
// macOS; elsewhere the freshest attached tmux client activity stands in.
// No signal at all reads as away — a machine nobody touched has nobody
// at it.
export function isPresent(
  inputIdleSecs: number | null,
  latestClientActivityTs: number | null,
  nowSecs: number,
): boolean {
  if (inputIdleSecs !== null) return inputIdleSecs < PRESENCE_IDLE_SECS;
  if (latestClientActivityTs !== null) {
    return nowSecs - latestClientActivityTs < PRESENCE_IDLE_SECS;
  }
  return false;
}

// Whether a terminal owns the screen. No focus signal (non-macOS, probe
// failure) keeps the old behavior: attachment alone counts as seeing.
export function terminalFocused(focusedApp: string | null): boolean {
  return focusedApp === null || TERMINAL_APP.test(focusedApp);
}
