#!/usr/bin/env node
// Assemble all component examples into one local preview.
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assemble } from "../build.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const [output, ...extra] = process.argv.slice(2);
if (!output || extra.length) {
  console.error("Usage: node scripts/fixture/build.mjs OUTPUT.html");
  process.exit(1);
}
const source = JSON.parse(await fs.readFile(path.join(here, "fixture.json")));
const pages = await Promise.all(
  source.pages.map(async ({ file, ...page }) => ({
    ...page,
    html: await fs.readFile(path.join(here, file), "utf8"),
  })),
);
const prototypes = await Promise.all(
  source.prototypes.map(async ({ file, ...prototype }) => ({
    ...prototype,
    html: await fs.readFile(path.join(here, file), "utf8"),
  })),
);
await fs.writeFile(output, await assemble({ ...source, pages, prototypes }), {
  flag: "wx",
  mode: 0o600,
});
console.log(path.resolve(output));
