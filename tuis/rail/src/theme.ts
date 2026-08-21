import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { XDG_STATE } from "./paths.js";

export interface Palette {
  mode: "dark" | "light";
  accent: string;
  notify: string;
  base: string;
  crust: string;
  surface0: string;
  text: string;
  dim: string;
  dim2: string;
  lavender: string;
  yellow: string;
  mauve: string;
  peach: string;
  green: string;
  red: string;
  // Agent status semantics, from the status_* tokens (tokens.conf) — the
  // same source tmux's @status_* variables render from.
  statusWorking: string;
  statusWaiting: string;
  statusDone: string;
}

// The rail's slab color: the darkest palette tier, so the sidebar fuses
// with the window frame it leans against.
export const railBg = (palette: Palette): string => palette.crust;

// The spec's single dim level: how much of a foreground survives when a
// row is de-emphasized (the elsewhere section, the timers).
export const DIM_KEEP = 0.55;

// TUIS_COLORS_PATH pins an alternate palette file (fixtures, light-mode
// checks) without touching the live theme state.
const PALETTE_PATH =
  process.env.TUIS_COLORS_PATH ??
  join(XDG_STATE, "dotfiles/generated/tuis-colors.json");

let cached: { palette: Palette; mtimeMs: number } | null = null;

// The theme system rewrites tuis-colors.json on every mode/mascot switch;
// re-reading on mtime change is what makes the rail converge live.
export function loadPalette(): Palette {
  const mtimeMs = statSync(PALETTE_PATH).mtimeMs;
  if (cached && cached.mtimeMs === mtimeMs) return cached.palette;
  const palette = JSON.parse(readFileSync(PALETTE_PATH, "utf8")) as Palette;
  cached = { palette, mtimeMs };
  return palette;
}

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
}

// Terminals have no opacity: the spec's "dimmed to 55%" becomes a real color
// mixed toward the rail background (keep = how much of the foreground survives).
export function blend(fg: string, bg: string, keep: number): string {
  const [fr, fg_, fb] = hexToRgb(fg);
  const [br, bg_, bb] = hexToRgb(bg);
  const mix = (f: number, b: number) => Math.round(f * keep + b * (1 - keep));
  const to2 = (v: number) => v.toString(16).padStart(2, "0");
  return `#${to2(mix(fr, br))}${to2(mix(fg_, bg_))}${to2(mix(fb, bb))}`;
}

// Escapes are memoized: a frame recolors the same ~16 palette hexes
// hundreds of times, and the cache never outgrows the palette.
const sgrCache = new Map<string, string>();

function sgr(prefix: 38 | 48, hex: string): string {
  const key = `${prefix}${hex}`;
  let esc = sgrCache.get(key);
  if (esc === undefined) {
    const [r, g, b] = hexToRgb(hex);
    esc = `\x1b[${prefix};2;${r};${g};${b}m`;
    sgrCache.set(key, esc);
  }
  return esc;
}

export const fg = (hex: string): string => sgr(38, hex);

export const bg = (hex: string): string => sgr(48, hex);

export const RESET = "\x1b[0m";
