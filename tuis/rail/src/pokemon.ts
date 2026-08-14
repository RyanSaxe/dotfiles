// Per-session pokemon identity. Each session's rail wears the pokemon
// mapped to its project (sessions are named after projects), falling back
// to the tracked default — accent color and sprite both.

import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

const STATE_MAPPING = join(
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
  "dotfiles/pokemon.conf",
);
// (The tracked default in ~/.config/theme/pokemon.conf is consumed by
// `theme pokemon sync`, whose result lands in accents.conf — the rail
// reads that, never the default directly.)
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

function parseConf(path: string): Map<string, string> {
  const entries = new Map<string, string>();
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    return entries;
  }
  for (const confLine of raw.split("\n")) {
    if (!confLine || confLine.startsWith("#")) continue;
    const eq = confLine.indexOf("=");
    if (eq < 1) continue;
    entries.set(confLine.slice(0, eq), confLine.slice(eq + 1));
  }
  return entries;
}

const identities = new Map<string, PokemonIdentity>();

function identityFor(value: string): PokemonIdentity {
  const cached = identities.get(value);
  if (cached) return cached;
  const shiny = value.endsWith(":shiny");
  const name = shiny ? value.slice(0, -6) : value;
  const spritePath = join(
    SPRITE_CACHE,
    `${name}${shiny ? "-shiny" : ""}-sprite.png`,
  );
  const identity: PokemonIdentity = {
    name,
    shiny,
    spritePath: existsSync(spritePath) ? spritePath : null,
    accentDark: null,
    accentLight: null,
  };
  identities.set(value, identity);
  void extractAccents(value, identity);
  return identity;
}

// Accent extraction runs the same extractor the theme system uses; slow
// (~1s) but cached for the daemon's lifetime per pokemon.
async function extractAccents(
  value: string,
  identity: PokemonIdentity,
): Promise<void> {
  try {
    const args = identity.shiny ? [identity.name, "--shiny"] : [identity.name];
    const { stdout } = await run(POKEMON_ACCENTS, args);
    const conf = new Map(
      stdout
        .split("\n")
        .filter((entry) => entry.includes("="))
        .map((entry) => {
          const eq = entry.indexOf("=");
          return [entry.slice(0, eq), entry.slice(eq + 1)] as const;
        }),
    );
    identity.accentDark = conf.get("accent_dark") ?? null;
    identity.accentLight = conf.get("accent_light") ?? null;
  } catch {
    // Extractor missing or failed: the theme accent stands in.
  }
}

const ACCENTS_CONF = join(
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
  "dotfiles/accents.conf",
);

// The globally ACTIVE pokemon (whatever `theme pokemon`/the picker last
// applied). Its accents are already extracted, so no extractor run.
function activeIdentity(): PokemonIdentity | null {
  const conf = parseConf(ACCENTS_CONF);
  const name = conf.get("pokemon");
  if (!name) return null;
  const shiny = conf.get("shiny") === "1";
  const spritePath = join(
    SPRITE_CACHE,
    `${name}${shiny ? "-shiny" : ""}-sprite.png`,
  );
  return {
    name,
    shiny,
    spritePath: existsSync(spritePath) ? spritePath : null,
    accentDark: conf.get("accent_dark") ?? null,
    accentLight: conf.get("accent_light") ?? null,
  };
}

// Session -> identity: the project's mapped pokemon wins; unmapped
// sessions follow the globally active one (which `theme pokemon sync`
// keeps aligned with the project you're in). Files are tiny and re-read
// each call, so picker changes land within a tick.
export function pokemonFor(session: string): PokemonIdentity | null {
  const mapped = parseConf(STATE_MAPPING).get(session);
  if (mapped) return identityFor(mapped);
  return activeIdentity();
}
