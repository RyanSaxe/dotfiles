// Cell-exact line assembly: every rail line is composed of colored spans,
// truncated by display width, and padded to the full rail width so the
// background paints edge to edge.

import { RESET, bg, fg } from "./theme.js";

export interface Span {
  text: string;
  fg: string;
  bg?: string;
}

// Minimal display-width model: wide (CJK/emoji) = 2 cells, zero-width
// (combining marks, variation selectors, ZWJ) = 0, everything else = 1.
// Agent titles are mostly ASCII plus glyphs like ✳ and braille spinners,
// all width 1 — this covers the realistic input space.
function charWidth(cp: number): number {
  if (
    cp === 0x200d || // zero-width joiner
    (cp >= 0xfe00 && cp <= 0xfe0f) || // variation selectors
    (cp >= 0x0300 && cp <= 0x036f) // combining marks
  ) {
    return 0;
  }
  if (
    (cp >= 0x1100 && cp <= 0x115f) ||
    (cp >= 0x2e80 && cp <= 0xa4cf) ||
    (cp >= 0xac00 && cp <= 0xd7a3) ||
    (cp >= 0xf900 && cp <= 0xfaff) ||
    (cp >= 0xfe30 && cp <= 0xfe4f) ||
    (cp >= 0xff00 && cp <= 0xff60) ||
    (cp >= 0xffe0 && cp <= 0xffe6) ||
    (cp >= 0x1f300 && cp <= 0x1faff) ||
    (cp >= 0x20000 && cp <= 0x3fffd)
  ) {
    return 2;
  }
  return 1;
}

export function displayWidth(text: string): number {
  let width = 0;
  for (const ch of text) width += charWidth(ch.codePointAt(0)!);
  return width;
}

export function truncate(text: string, max: number): string {
  if (displayWidth(text) <= max) return text;
  let width = 0;
  let out = "";
  for (const ch of text) {
    const w = charWidth(ch.codePointAt(0)!);
    if (width + w > max - 1) break;
    out += ch;
    width += w;
  }
  return out + "…";
}

// Compose left-aligned spans plus an optional right-aligned span into one
// line exactly `width` cells wide, painted on `lineBg`. The last flexible
// span (marked by flex) absorbs truncation; the right span never truncates.
export function line(
  width: number,
  lineBg: string,
  spans: Span[],
  right?: Span,
): string {
  // Right-aligned spans end flush at the final column; left content keeps
  // at least one cell of air before them.
  const rightWidth = right ? displayWidth(right.text) : 0;
  let used = 0;
  let out = bg(lineBg);
  const parts: Span[] = [];
  const budget = width - rightWidth - (right ? 1 : 0);
  for (const span of spans) {
    const available = budget - used;
    if (available <= 0) break;
    const text = truncate(span.text, available);
    parts.push({ ...span, text });
    used += displayWidth(text);
  }
  for (const span of parts) {
    out += bg(span.bg ?? lineBg) + fg(span.fg) + span.text;
    if (span.bg) out += bg(lineBg);
  }
  const fill = width - used - rightWidth;
  out += " ".repeat(Math.max(0, fill));
  if (right) out += fg(right.fg) + right.text;
  return out + RESET;
}

export function blank(width: number, lineBg: string): string {
  return bg(lineBg) + " ".repeat(width) + RESET;
}

export function fmtElapsed(secs: number): string {
  // Minute floor: a seconds readout would tick every second and keep the
  // rail in constant motion; nothing under a minute is worth reading.
  if (secs < 60) return "<1m";
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h`;
  return `${Math.floor(secs / 86400)}d`;
}
