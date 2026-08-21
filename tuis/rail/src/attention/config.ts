import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { GitHubActor } from "./types.js";

// A repository to hear about even when you are not involved in it.
export interface WatchedRepository {
  repository: string;
  pullRequests: boolean;
  issues: boolean;
}

export interface AttentionConfig {
  actors: {
    allow: string[];
    ignore: string[];
  };
  ownPrCi: boolean;
  watch: WatchedRepository[];
}

const DEFAULT_CONFIG: AttentionConfig = {
  actors: { allow: [], ignore: [] },
  ownPrCi: true,
  watch: [],
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringList(value: unknown, field: string, path: string): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new Error(
      `attention config ${path}: ${field} must be an array of GitHub logins`,
    );
  }
  return value.map((item) => normalizeLogin(item)).filter(Boolean);
}

export function normalizeLogin(login: string): string {
  return login.trim().replace(/^@/, "").toLowerCase();
}

export function defaultAttentionConfig(): AttentionConfig {
  return {
    actors: {
      allow: [...DEFAULT_CONFIG.actors.allow],
      ignore: [...DEFAULT_CONFIG.actors.ignore],
    },
    ownPrCi: DEFAULT_CONFIG.ownPrCi,
    watch: [],
  };
}

const REPOSITORY = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/;

function watchList(value: unknown, path: string): WatchedRepository[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new Error(
      `attention config ${path}: watch must be an array of { "repo": "owner/name" } entries`,
    );
  }
  const seen = new Set<string>();
  return value.map((entry, index) => {
    if (!isRecord(entry)) {
      throw new Error(
        `attention config ${path}: watch[${index}] must be an object with a "repo" key`,
      );
    }
    const repository = entry["repo"];
    if (typeof repository !== "string" || !REPOSITORY.test(repository)) {
      throw new Error(
        `attention config ${path}: watch[${index}].repo must be "owner/name", got ${JSON.stringify(repository)}`,
      );
    }
    const key = repository.toLowerCase();
    if (seen.has(key)) {
      throw new Error(
        `attention config ${path}: watch lists ${repository} more than once`,
      );
    }
    seen.add(key);
    const flag = (name: string): boolean => {
      const raw = entry[name];
      if (raw === undefined) return true;
      if (typeof raw !== "boolean") {
        throw new Error(
          `attention config ${path}: watch[${index}].${name} must be true or false`,
        );
      }
      return raw;
    };
    return {
      repository,
      pullRequests: flag("pull_requests"),
      issues: flag("issues"),
    };
  });
}

export function validateAttentionConfig(
  value: unknown,
  path: string,
): AttentionConfig {
  if (!isRecord(value)) {
    throw new Error(`attention config ${path}: expected a JSON object`);
  }

  const actorsValue = value["actors"];
  const actors = isRecord(actorsValue) ? actorsValue : {};
  const allow = stringList(actors["allow"], "actors.allow", path);
  const ignore = stringList(actors["ignore"], "actors.ignore", path);
  const overlap = allow.filter((login) => ignore.includes(login));
  if (overlap.length > 0) {
    throw new Error(
      `attention config ${path}: actor(s) cannot be both allowed and ignored: ${overlap.join(
        ", ",
      )}`,
    );
  }

  const ownPrCi = value["own_pr_ci"] ?? value["ownPrCi"] ?? true;
  if (typeof ownPrCi !== "boolean") {
    throw new Error(
      `attention config ${path}: own_pr_ci must be true or false`,
    );
  }

  return {
    actors: { allow, ignore },
    ownPrCi,
    watch: watchList(value["watch"], path),
  };
}

export function attentionConfigPath(): string {
  return (
    process.env["DOTFILES_ATTENTION_CONFIG"] ??
    join(
      process.env["XDG_CONFIG_HOME"] ?? join(homedir(), ".config"),
      "dotfiles",
      "attention.json",
    )
  );
}

export function loadAttentionConfig(
  path = attentionConfigPath(),
): AttentionConfig {
  if (!existsSync(path)) return defaultAttentionConfig();
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
  } catch (error) {
    throw new Error(
      `attention config ${path}: invalid JSON (${String(error)})`,
    );
  }
  return validateAttentionConfig(parsed, path);
}

export function actorIsEligible(
  actor: GitHubActor | null,
  config: AttentionConfig,
): boolean {
  if (actor === null) return false;
  const login = normalizeLogin(actor.login);
  if (config.actors.ignore.includes(login)) return false;
  if (config.actors.allow.includes(login)) return true;
  return actor.kind === "user";
}
