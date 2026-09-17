import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);
const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const skill = path.join(repoRoot, "ai-harness/skills/visual-review");

test("SKILL.md declares only the frontmatter every harness accepts", async () => {
  const source = await fs.readFile(path.join(skill, "SKILL.md"), "utf8");
  const frontmatter = source.match(/^---\n([\s\S]*?)\n---\n/);
  assert.ok(frontmatter, "SKILL.md needs YAML frontmatter");
  const keys = frontmatter[1]
    .split("\n")
    .map((line) => line.match(/^([a-z-]+):/)?.[1])
    .filter(Boolean);
  assert.deepEqual(keys, ["name", "description"]);
  assert.match(frontmatter[1], /^name: visual-review$/m);
  assert.match(
    frontmatter[1],
    /explicitly invokes visual-review by name/,
    "the description must keep the skill from being invoked implicitly",
  );
});

test("the Codex policy forbids implicit invocation", async () => {
  const policy = await fs.readFile(
    path.join(skill, "agents/openai.yaml"),
    "utf8",
  );
  assert.match(policy, /allow_implicit_invocation:\s*false/);
});

test("the environment check reports a usable repository", async () => {
  const { stdout } = await run(
    process.execPath,
    [path.join(skill, "scripts/check.mjs")],
    { cwd: repoRoot },
  );
  const report = JSON.parse(stdout);
  assert.equal(report.ready, true);
  assert.equal(report.repository, repoRoot);
});
