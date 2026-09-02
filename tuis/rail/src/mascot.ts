// Per-session mascot identity. Each session's rail wears the mascot
// mapped to its project (sessions are named after projects), falling back
// to the tracked default — accent color and sprite both.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { run } from "./data.js";
import { XDG_STATE } from "./paths.js";

const STATE_MAPPING = join(XDG_STATE, "dotfiles/mascot.conf");
// The tracked global default, mirrored into state by `theme mascot
// default` (the rail cannot reach the repo-tracked config file).
const STATE_DEFAULT = join(XDG_STATE, "dotfiles/mascot-default.conf");
// (The tracked default in ~/.config/theme/mascot.conf is consumed by
// `theme mascot sync`, whose result lands in accents.conf — the rail
// reads that, never the default directly.)
const ACCENTS_CONF = join(XDG_STATE, "dotfiles/accents.conf");
// The theme script caches extraction results per mascot per extractor
// version (accents-<astamp>/<key>.conf). The rail only reads that cache —
// the theme script stays its sole writer.
const THEME_CACHE = join(XDG_STATE, "dotfiles/cache/theme");
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

// How long a failed extraction stays cached before a tick retries it.
const EXTRACT_RETRY_MS = 30_000;

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

// The theme script's cache key: anything outside its conservative set
// collapses to '-' (same tr class as `mascot_key` in theme/bin/theme).
function mascotKey(value: string): string {
  return value.replace(/[^A-Za-z0-9._\n-]/g, "-");
}

// Look up the theme script's accents cache; the mascot= line inside the
// conf disambiguates the lossy key. Newest generation wins when an
// unpruned older one still lingers.
function cachedAccents(value: string): Map<string, string> | null {
  try {
    const generations = readdirSync(THEME_CACHE)
      .filter((name) => name.startsWith("accents-"))
      .map((name) => join(THEME_CACHE, name))
      .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
    for (const dir of generations) {
      const path = join(dir, `${mascotKey(value)}.conf`);
      if (!existsSync(path)) continue;
      const conf = parseConfText(readFileSync(path, "utf8"));
      if (conf.get("mascot") === value) return conf;
    }
  } catch {
    // Unreadable cache = miss; the extractor below covers it.
  }
  return null;
}

// Accents and the sprite pointer come from the same extractor the theme
// system uses — the rail never hardcodes any provider's cache layout.
// The theme script's accents cache answers first (pure file read); the
// extractor (~1s uv/python) only runs for a mascot the theme system has
// never extracted on this machine.
async function extract(identity: MascotIdentity): Promise<void> {
  const cached = cachedAccents(identity.value);
  if (cached) {
    identity.spritePath = cached.get("sprite") ?? null;
    identity.accentDark = cached.get("accent_dark") ?? null;
    identity.accentLight = cached.get("accent_light") ?? null;
    return;
  }
  try {
    const { stdout } = await run(MASCOT_ACCENTS, [identity.value]);
    const conf = parseConfText(stdout);
    identity.spritePath = conf.get("sprite") ?? null;
    identity.accentDark = conf.get("accent_dark") ?? null;
    identity.accentLight = conf.get("accent_light") ?? null;
  } catch {
    // Extractor failed (cold uv env, network blip): the theme accent
    // stands in meanwhile, but the failure must not pin this identity to
    // nulls until daemon restart — forget it after a beat so a later tick
    // retries. The delay keeps a persistently failing extractor from
    // respawning on every refresh.
    setTimeout(() => identities.delete(identity.value), EXTRACT_RETRY_MS);
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
  // Unmapped sessions wear the tracked global default (mirrored into
  // state by `theme mascot default`), not whatever accent happens to be
  // published — the published accent follows the ACTIVE session, which
  // may be a mapped one.
  const fallback = parseConf(STATE_DEFAULT).get("default");
  if (fallback) return identityFor(fallback);
  // Installs that predate the mirror: the published accent is the best
  // remaining guess.
  return activeIdentity();
}
