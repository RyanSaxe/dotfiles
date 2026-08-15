// Per-session mascot identity. Each session's rail wears the mascot
// mapped to its project (sessions are named after projects), falling back
// to the tracked default — accent color and sprite both.

import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { run } from "./data.js";
import { XDG_STATE } from "./paths.js";

const STATE_MAPPING = join(XDG_STATE, "dotfiles/mascot.conf");
// (The tracked default in ~/.config/theme/mascot.conf is consumed by
// `theme mascot sync`, whose result lands in accents.conf — the rail
// reads that, never the default directly.)
const ACCENTS_CONF = join(XDG_STATE, "dotfiles/accents.conf");
const MASCOT_ACCENTS = join(homedir(), ".local/bin/mascot-accents");

export interface MascotIdentity {
  // Provider-qualified, e.g. "pokemon:raikou".
  value: string;
  // Path to the provider's normalized sprite; null until extraction lands.
  spritePath: string | null;
  // Hexes per mode, extracted from the provider's image; null until
  // extraction lands (frames render with the theme accent meanwhile).
  accentDark: string | null;
  accentLight: string | null;
}

function parseConfText(raw: string): Map<string, string> {
  const entries = new Map<string, string>();
  for (const confLine of raw.split("\n")) {
    if (!confLine || confLine.startsWith("#")) continue;
    const eq = confLine.indexOf("=");
    if (eq < 1) continue;
    entries.set(confLine.slice(0, eq), confLine.slice(eq + 1));
  }
  return entries;
}

// Conf reads are mtime-gated (the loadPalette pattern): identical
// freshness, zero re-parsing while nothing changed — this runs per rail
// pane per tick.
const confCache = new Map<
  string,
  { mtimeMs: number; conf: Map<string, string> }
>();

function parseConf(path: string): Map<string, string> {
  try {
    const mtimeMs = statSync(path).mtimeMs;
    const cached = confCache.get(path);
    if (cached && cached.mtimeMs === mtimeMs) return cached.conf;
    const conf = parseConfText(readFileSync(path, "utf8"));
    confCache.set(path, { mtimeMs, conf });
    return conf;
  } catch {
    return new Map();
  }
}

const identities = new Map<string, MascotIdentity>();

function identityFor(value: string): MascotIdentity {
  const cached = identities.get(value);
  if (cached) return cached;
  const identity: MascotIdentity = {
    value,
    spritePath: null,
    accentDark: null,
    accentLight: null,
  };
  identities.set(value, identity);
  void extract(identity);
  return identity;
}

// Accents and the sprite pointer come from the same extractor the theme
// system uses — the rail never hardcodes any provider's cache layout.
// Slow (~1s) but cached for the daemon's lifetime per mascot.
async function extract(identity: MascotIdentity): Promise<void> {
  try {
    const { stdout } = await run(MASCOT_ACCENTS, [identity.value]);
    const conf = parseConfText(stdout);
    identity.spritePath = conf.get("sprite") ?? null;
    identity.accentDark = conf.get("accent_dark") ?? null;
    identity.accentLight = conf.get("accent_light") ?? null;
  } catch {
    // Extractor missing or failed: the theme accent stands in.
  }
}

// The globally ACTIVE mascot (whatever `theme mascot`/the picker last
// applied). accents.conf already carries its hexes and sprite pointer,
// so no extractor run.
function activeIdentity(): MascotIdentity | null {
  const conf = parseConf(ACCENTS_CONF);
  const value = conf.get("mascot");
  if (!value) return null;
  const sprite = conf.get("sprite");
  return {
    value,
    spritePath: sprite && existsSync(sprite) ? sprite : null,
    accentDark: conf.get("accent_dark") ?? null,
    accentLight: conf.get("accent_light") ?? null,
  };
}

// Session -> identity: the project's mapped mascot wins; unmapped
// sessions follow the globally active one (which `theme mascot sync`
// keeps aligned with the project you're in). Conf reads are mtime-gated
// above, so picker changes still land within a tick.
export function mascotFor(session: string): MascotIdentity | null {
  const mapped = parseConf(STATE_MAPPING).get(session);
  if (mapped) return identityFor(mapped);
  return activeIdentity();
}
