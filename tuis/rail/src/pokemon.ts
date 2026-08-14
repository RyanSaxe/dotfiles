// Per-session pokemon identity. Each session's rail wears the pokemon
// mapped to its project (sessions are named after projects), falling back
// to the tracked default — accent color and sprite both.

import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { run } from "./data.js";
import { XDG_STATE } from "./paths.js";

const STATE_MAPPING = join(XDG_STATE, "dotfiles/pokemon.conf");
// (The tracked default in ~/.config/theme/pokemon.conf is consumed by
// `theme pokemon sync`, whose result lands in accents.conf — the rail
// reads that, never the default directly.)
const ACCENTS_CONF = join(XDG_STATE, "dotfiles/accents.conf");
const SPRITE_CACHE = join(homedir(), ".cache/dotfiles/pokemon");
const POKEMON_ACCENTS = join(homedir(), ".local/bin/pokemon-accents");

export interface PokemonIdentity {
  name: string;
  shiny: boolean;
  spritePath: string | null;
  // Hexes per mode, extracted from the sprite; null until extraction lands
  // (frames render with the theme accent meanwhile).
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

// The sprite-cache naming convention, in exactly one place (it mirrors
// what pokemon-accents writes).
function spritePathFor(name: string, shiny: boolean): string | null {
  const path = join(SPRITE_CACHE, `${name}${shiny ? "-shiny" : ""}-sprite.png`);
  return existsSync(path) ? path : null;
}

const identities = new Map<string, PokemonIdentity>();

function identityFor(value: string): PokemonIdentity {
  const cached = identities.get(value);
  if (cached) return cached;
  const shiny = value.endsWith(":shiny");
  const name = shiny ? value.slice(0, -6) : value;
  const identity: PokemonIdentity = {
    name,
    shiny,
    spritePath: spritePathFor(name, shiny),
    accentDark: null,
    accentLight: null,
  };
  identities.set(value, identity);
  void extractAccents(identity);
  return identity;
}

// Accent extraction runs the same extractor the theme system uses; slow
// (~1s) but cached for the daemon's lifetime per pokemon.
async function extractAccents(identity: PokemonIdentity): Promise<void> {
  try {
    const args = identity.shiny ? [identity.name, "--shiny"] : [identity.name];
    const { stdout } = await run(POKEMON_ACCENTS, args);
    const conf = parseConfText(stdout);
    identity.accentDark = conf.get("accent_dark") ?? null;
    identity.accentLight = conf.get("accent_light") ?? null;
  } catch {
    // Extractor missing or failed: the theme accent stands in.
  }
}

// The globally ACTIVE pokemon (whatever `theme pokemon`/the picker last
// applied). Its accents are already extracted, so no extractor run.
function activeIdentity(): PokemonIdentity | null {
  const conf = parseConf(ACCENTS_CONF);
  const name = conf.get("pokemon");
  if (!name) return null;
  const shiny = conf.get("shiny") === "1";
  return {
    name,
    shiny,
    spritePath: spritePathFor(name, shiny),
    accentDark: conf.get("accent_dark") ?? null,
    accentLight: conf.get("accent_light") ?? null,
  };
}

// Session -> identity: the project's mapped pokemon wins; unmapped
// sessions follow the globally active one (which `theme pokemon sync`
// keeps aligned with the project you're in). Conf reads are mtime-gated
// above, so picker changes still land within a tick.
export function pokemonFor(session: string): PokemonIdentity | null {
  const mapped = parseConf(STATE_MAPPING).get(session);
  if (mapped) return identityFor(mapped);
  return activeIdentity();
}
