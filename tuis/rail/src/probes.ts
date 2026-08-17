// Host-level probes, collected once per tick. The decisions they feed are
// pure functions of the probed values so the routing logic stays testable
// without a macOS session behind it.

import { platform } from "node:os";

import { run } from "./data.js";

// No system input for this long means nobody is at the desk and the phone
// is the channel. Tunable.
export const PRESENCE_IDLE_SECS = 120;

export interface HostFacts {
  // Seconds since the last keyboard/mouse input; null when unprobeable.
  inputIdleSecs: number | null;
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

export async function collectHostFacts(): Promise<HostFacts> {
  if (platform() !== "darwin") return { inputIdleSecs: null };
  return { inputIdleSecs: await probeInputIdle() };
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
