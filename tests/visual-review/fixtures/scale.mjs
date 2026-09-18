#!/usr/bin/env node
/**
 * Serve a session on the 100,000-file repository, with one answer that cites
 * a 20,000-line file, so the budget can be felt by hand: quick open as you
 * type, a long file opening on its cited lines, an ignored directory absent.
 *
 *   node tests/visual-review/fixtures/scale.mjs
 */
import fs from "node:fs/promises";
import path from "node:path";
import { serve } from "../../../ai-harness/skills/visual-review/scripts/session.mjs";
import {
  createLargeRepository,
  inspect,
  removeAll,
  temporaryDirectory,
} from "./repo.mjs";

const started = Date.now();
const repo = await createLargeRepository();
const lines = [];
for (let n = 0; lines.length < 20_000; n += 1) {
  lines.push(`def case_${n}(value):`);
  for (let i = 0; i < 8; i += 1) lines.push(`    value = value + ${i}`);
  lines.push("    return value", "");
}
lines.length = 20_000;
// fast-import wrote the commit and nothing else; the index must match HEAD
// before one more file is added, or the next commit holds only that file.
await inspect(repo.root, ["reset", "-q"]);
await fs.mkdir(path.join(repo.root, "src"), { recursive: true });
await fs.writeFile(path.join(repo.root, "src/big.py"), lines.join("\n") + "\n");
await inspect(repo.root, ["add", "src/big.py"]);
await inspect(repo.root, ["commit", "--quiet", "-m", "big"]);
const built = Date.now() - started;

const sessionDir = await temporaryDirectory("scale");
const session = await serve(sessionDir, { repo: repo.root });
const { token } = JSON.parse(
  await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
);
async function post(route, headers, body) {
  const response = await fetch(session.origin + route, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify({ sessionId: session.sessionId, ...body }),
  });
  const result = await response.json();
  if (!response.ok)
    throw new Error(`${route} ${JSON.stringify(body)}: ${result.error}`);
  return result;
}
const browser = (route, body) => post(route, { Origin: session.origin }, body);
const agent = (body) =>
  post("/agent/action", { authorization: `Bearer ${token}` }, body);

await browser("/api/ask", {
  id: "scale1",
  text: "Where is case 10000 handled?",
});
await agent({ action: "ack", id: "scale1" });
await agent({
  action: "plan",
  question: "scale1",
  title: "One case in a big file",
  pages: "case=The case",
});
await agent({
  action: "page",
  question: "scale1",
  id: "case",
  markdown:
    "```code src/big.py:10001-10010\n10001  One of two thousand identical cases.\n```\n\nThe file has 20,000 lines; the pane opens on these.\n",
});
await agent({ action: "done", question: "scale1" });
console.log(
  `\n  ${session.origin}\n  repo ${repo.root} (built in ${built} ms)\n  press Ctrl-C to stop\n`,
);
for (const signal of ["SIGINT", "SIGTERM"])
  process.once(signal, async () => {
    await session.close();
    await removeAll(sessionDir, repo.root);
    process.exit(0);
  });
