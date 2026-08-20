#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function loadColors() {
  const stateHome =
    process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
  const generated = path.join(
    stateHome,
    "dotfiles",
    "generated",
    "ai-statusline-colors.js",
  );

  try {
    return require(generated);
  } catch (_error) {
    // The status line remains useful before the first `theme apply`.
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
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`;
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

function gitInfo(cwd, colors) {
  try {
    execFileSync("git", ["-C", cwd, "rev-parse", "--git-dir"], {
      stdio: ["ignore", "ignore", "ignore"],
    });
  } catch (_error) {
    return "";
  }

  let branch = "detached";
  try {
    branch =
      execFileSync("git", ["-C", cwd, "branch", "--show-current"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim() || "detached";
  } catch (_error) {
    // Keep the detached label when the branch cannot be read.
  }

  let dirty = false;
  try {
    dirty =
      execFileSync("git", ["-C", cwd, "status", "--porcelain"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim().length > 0;
  } catch (_error) {
    // A missing status is less useful than the branch, so keep going.
  }

  const mark = dirty ? "●" : "✓";
  const role = dirty ? "waiting" : "done";
  return ` ${colorize(colors, "muted", "on")} ${colorize(colors, "accent", branch)} ${colorize(colors, role, mark)}`;
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
  const modelLabel = effort ? `${model}/${effort}` : model;

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
  const contextLabel =
    remaining === undefined && tokens === undefined
      ? ""
      : ` [ctx: ${tokens ? `${tokens} ` : ""}${remaining === undefined ? "" : `${Math.round(remaining)}% left`}]`;

  const line = `${colorize(colors, "muted", "in")} ${colorize(colors, "info", directory)}${gitInfo(cwd, colors)} ${colorize(colors, "muted", "with")} ${colorize(colors, "working", modelLabel)}${colorize(colors, "muted", contextLabel)}`;
  process.stdout.write(`${line}\n`);
}

main();
