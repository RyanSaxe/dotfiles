#!/usr/bin/env node
/**
 * Play a canned answer through a real helper so the frame can be used by hand.
 *
 * Builds the sample repository, starts a session on it, asks a question as the
 * browser would, then plans and publishes the fixture pages one at a time.
 * Prints the URL and stays up until interrupted.
 *
 *   node tests/visual-review/fixtures/play.mjs [--delay 1500]
 */
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { serve } from "../../../ai-harness/skills/visual-review/scripts/session.mjs";
import {
  createSampleRepository,
  inspect,
  removeAll,
  temporaryDirectory,
} from "./repo.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const delay = Number(
  process.argv.includes("--delay")
    ? process.argv[process.argv.indexOf("--delay") + 1]
    : 1500,
);
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Commit a 773-line module so the code pane has something to fold, with the
 * cited lines inside `submit` and definitions above and below them, and a
 * 20,000-line one for the pane's budget.
 */
async function addLongFile(root) {
  const lines = [];
  const filler = (name, count) => {
    lines.push(`def ${name}(request):`);
    for (let i = 0; i < count; i += 1)
      lines.push(`    step_${i} = request.get("${name}", ${i})`);
    lines.push("    return request", "", "");
  };
  for (let n = 0; lines.length < 330; n += 1) filler(`prepare_${n}`, 10);
  lines.push(
    "def submit(request, ledger):",
    '    """Charge once, retrying only RetryableError."""',
    "    attempt = 0",
    "    while attempt < Client.ATTEMPTS:",
    "        try:",
    "            receipt = gateway.post(request)",
    "        except RetryableError:",
    "            attempt += 1",
    "            continue",
    "        ledger.append(receipt)",
    "        return receipt",
    "    raise GaveUp(attempt)",
    "",
    "",
  );
  for (let n = 0; lines.length < 773; n += 1) filler(`settle_${n}`, 10);
  lines.length = 773;
  await fs.writeFile(
    path.join(root, "src/session.py"),
    lines.join("\n") + "\n",
  );
  const generated = [];
  for (let n = 0; generated.length < 20_000; n += 1) {
    generated.push(`def case_${n}(value):`);
    for (let i = 0; i < 8; i += 1) generated.push(`    value = value + ${i}`);
    generated.push("    return value", "");
  }
  generated.length = 20_000;
  await fs.writeFile(
    path.join(root, "src/generated.py"),
    generated.join("\n") + "\n",
  );
  await inspect(root, ["add", "src/session.py", "src/generated.py"]);
  await inspect(root, ["commit", "--quiet", "-m", "session"]);
}

const pages = [
  ["overview", "Overview map", "overview.md"],
  ["excerpt", "The retry loop", "excerpt.md"],
  ["change", "What PR 7 changes", "change.md"],
  ["walkthrough", "A charge, end to end", "walkthrough.md"],
  ["notes", "Notes on the client", "notes.md"],
];

const repo = await createSampleRepository();
await addLongFile(repo.root);
const sessionDir = await temporaryDirectory("play");
const session = await serve(sessionDir, { repo: repo.root });
const { token } = JSON.parse(
  await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
);

/** Post and fail loudly: a fixture that swallows an error teaches nothing. */
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

console.log(
  `\n  ${session.origin}\n  session ${sessionDir}\n  repo    ${repo.root}\n`,
);

await browser("/api/ask", {
  id: "play1",
  text: "How does a charge reach the ledger, and what does PR 7 change?",
});
await agent({ action: "ack", id: "play1" });
await pause(delay);
await agent({
  action: "plan",
  question: "play1",
  title: "Charges and PR 7",
  pages: pages.map(([id, title]) => `${id}=${title}`).join(","),
});

for (const [id, title, file] of pages) {
  await agent({
    action: "status",
    question: "play1",
    text: `writing ${title.toLowerCase()}`,
  });
  await pause(delay);
  await agent({
    action: "page",
    question: "play1",
    id,
    markdown: await fs.readFile(path.join(here, "pages", file), "utf8"),
  });
}
await agent({ action: "done", question: "play1" });
console.log("  answer complete; press Ctrl-C to stop\n");

for (const signal of ["SIGINT", "SIGTERM"])
  process.once(signal, async () => {
    await session.close();
    await removeAll(sessionDir, repo.root, repo.origin);
    process.exit(0);
  });
