#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function loadColors() {
  const generated = path.join(
    os.homedir(),
    ".config",
    "theme",
    "ai-statusline-colors.js",
  );

  try {
    return require(generated);
  } catch (_error) {
    // The status line remains useful before the first home switch.
    return {};
  }
}

function readInput() {
  try {
    return JSON.parse(fs.readFileSync(0, "utf8"));
  } catch (_error) {
    return {};
  }
}

function nested(value, ...keys) {
  return keys.reduce((current, key) => {
    if (current === null || typeof current !== "object") return undefined;
    return current[key];
  }, value);
}

function firstDefined(...values) {
  return values.find(
    (value) => value !== undefined && value !== null && value !== "",
  );
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function formatTokens(value) {
  const tokens = number(value);
  if (tokens === undefined || tokens <= 0) return undefined;
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (tokens >= 1_000) return `${Math.round(tokens / 1_000)}k`;
  return String(Math.round(tokens));
}

function colorize(colors, name, value) {
  const color = colors[name] || "";
  const match = /^#([0-9a-f]{6})$/i.exec(color);
  const prefix = match
    ? `\u001b[38;2;${Number.parseInt(match[1].slice(0, 2), 16)};${Number.parseInt(match[1].slice(2, 4), 16)};${Number.parseInt(match[1].slice(4, 6), 16)}m`
    : "";
  const reset = "\u001b[0m";
  return prefix ? `${prefix}${value}${reset}` : value;
}

function git(cwd, args) {
  return execFileSync("git", ["-C", cwd, ...args], {
    encoding: "utf8",
    // Like the prompt, never take index.lock: the agent's own git commands
    // run while the status line refreshes.
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" },
    stdio: ["ignore", "pipe", "ignore"],
  });
}

// The prompt's branch, its color when upstream is ahead, and its clean or
// dirty mark, from the same `git status` call prompt-segments.sh makes.
function gitInfo(cwd, colors) {
  let status;
  try {
    status = git(cwd, ["status", "--porcelain=v2", "--branch"]);
  } catch (_error) {
    return "";
  }

  let branch = "";
  let behind = 0;
  let dirty = false;
  for (const line of status.split("\n")) {
    if (line.startsWith("# branch.head ")) {
      branch = line.slice("# branch.head ".length);
    } else if (line.startsWith("# branch.ab ")) {
      behind = Number(line.split(" ")[3].slice(1));
    } else if (line && !line.startsWith("#")) {
      dirty = true;
      break;
    }
  }
  if (branch === "(detached)") {
    try {
      branch = git(cwd, ["rev-parse", "--short", "HEAD"]).trim();
    } catch (_error) {
      branch = "";
    }
  }

  const branchLabel = branch
    ? ` ${colorize(colors, "faint", "on")} ${colorize(colors, behind > 0 ? "branchBehind" : "branch", branch)}`
    : "";
  const mark = dirty
    ? colorize(colors, "dirty", "✗")
    : colorize(colors, "clean", "✓");
  return `${branchLabel} ${mark}`;
}

function main() {
  const data = readInput();
  const colors = loadColors();
  const cwd = String(
    firstDefined(
      nested(data, "workspace", "current_dir"),
      data.cwd,
      process.cwd(),
    ),
  );
  const directory = path.basename(cwd) || cwd;
  const model = String(
    firstDefined(
      nested(data, "model", "display_name"),
      nested(data, "model", "id"),
      "agent",
    ),
  );
  const effort = firstDefined(
    nested(data, "effort", "level"),
    data.effortLevel,
  );

  const context = data.context_window || {};
  const used = number(
    firstDefined(
      context.used_percentage,
      context.current_context_used_percentage,
    ),
  );
  const remaining = number(
    firstDefined(
      context.remaining_percentage,
      used === undefined ? undefined : 100 - used,
    ),
  );
  const tokens = formatTokens(
    firstDefined(
      context.current_context_tokens,
      context.total_input_tokens,
      nested(context, "current_usage", "input_tokens"),
    ),
  );
  const details = [
    effort,
    tokens,
    remaining === undefined ? undefined : `${Math.round(remaining)}% left`,
  ].filter(Boolean);

  const line = `${colorize(colors, "faint", "in")} ${colorize(colors, "project", directory)}${gitInfo(cwd, colors)} ${colorize(colors, "faint", "with")} ${colorize(colors, "model", model)}${details.length ? ` ${colorize(colors, "faint", details.join(" "))}` : ""}`;
  process.stdout.write(`${line}\n`);
}

main();
