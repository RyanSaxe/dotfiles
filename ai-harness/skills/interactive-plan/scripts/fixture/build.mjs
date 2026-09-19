#!/usr/bin/env node
// Builds the fixture artifact. The component styles and behaviors are
// concatenated here at build time, so the fixture never drifts from them.
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "../build.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const components = path.join(here, "..", "..", "components");
const [output, ...extra] = process.argv.slice(2);
if (!output || extra.length) {
  console.error("Usage: node scripts/fixture/build.mjs OUTPUT.html");
  process.exit(1);
}
const names = (await fs.readdir(components, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();
const gather = async (file) =>
  (
    await Promise.all(
      names.map((name) =>
        fs.readFile(path.join(components, name, file), "utf8").catch(() => ""),
      ),
    )
  ).join("\n");
const work = await fs.mkdtemp(path.join(os.tmpdir(), "plan-fixture-"));
try {
  for (const entry of await fs.readdir(here))
    await fs.copyFile(path.join(here, entry), path.join(work, entry));
  await fs.writeFile(
    path.join(work, "fixture.css"),
    await gather("styles.css"),
  );
  await fs.writeFile(
    path.join(work, "fixture.js"),
    await gather("behavior.js"),
  );
  await fs.writeFile(output, await build(path.join(work, "fixture.json")), {
    flag: "wx",
    mode: 0o600,
  });
  console.log(path.resolve(output));
} finally {
  await fs.rm(work, { recursive: true, force: true });
}
