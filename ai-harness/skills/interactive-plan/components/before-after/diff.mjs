#!/usr/bin/env node
import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);

export async function compareFiles(beforePath, afterPath) {
  const paths = [beforePath, afterPath].map((file) => path.resolve(file));
  const [before, after] = await Promise.all(
    paths.map((file) => fs.readFile(file, "utf8")),
  );
  if (before.includes("\0") || after.includes("\0"))
    throw Error("The diff viewer accepts text files, not binary files.");
  let patch;
  try {
    ({ stdout: patch } = await run(
      "git",
      [
        "diff",
        "--no-index",
        "--no-ext-diff",
        "--no-textconv",
        "--no-color",
        ...paths,
      ],
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    ));
  } catch (error) {
    if (error.code === 1) patch = error.stdout;
    else if (error.code === "ENOENT")
      throw Error("Git is required to generate a diff.");
    else throw Error(error.stderr?.trim() || error.message);
  }
  return { before, after, patch: named(patch, path.basename(paths[1])) };
}

/* git names both sides by the paths it was given, which for scratch copies
   are absolute temp paths the reader sees in the patch. The headers name
   the file instead, as a patch from the file's own repository would. */
function named(patch, name) {
  const lines = patch.split("\n");
  for (let i = 0; i < lines.length && !lines[i].startsWith("@@"); i++) {
    if (lines[i].startsWith("diff --git "))
      lines[i] = `diff --git a/${name} b/${name}`;
    else if (lines[i].startsWith("--- ")) lines[i] = `--- a/${name}`;
    else if (lines[i].startsWith("+++ ")) lines[i] = `+++ b/${name}`;
  }
  return lines.join("\n");
}

// Compare real paths: the skill is installed through a symlink, and a guard
// on the spelling alone exits without running anything.
const invoked = (() => {
  try {
    return (
      Boolean(process.argv[1]) &&
      realpathSync(path.resolve(process.argv[1])) ===
        realpathSync(fileURLToPath(import.meta.url))
    );
  } catch {
    return false;
  }
})();

if (invoked) {
  try {
    const [before, after, output, ...extra] = process.argv.slice(2);
    if (!before || !after || !output || extra.length)
      throw Error(
        "Usage: node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json",
      );
    const input = await compareFiles(before, after);
    await fs.writeFile(output, JSON.stringify(input, null, 2) + "\n", {
      flag: "wx",
      mode: 0o600,
    });
    console.log(path.resolve(output));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
