#!/usr/bin/env node
// Builds the fixture artifact. The builder bundles every component, so the
// fixture renders whatever components/ holds and cannot drift from them.
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "../build.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const [output, ...extra] = process.argv.slice(2);
if (!output || extra.length) {
  console.error("Usage: node scripts/fixture/build.mjs OUTPUT.html");
  process.exit(1);
}
await fs.writeFile(output, await build(path.join(here, "fixture.json")), {
  flag: "wx",
  mode: 0o600,
});
console.log(path.resolve(output));
