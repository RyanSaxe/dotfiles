#!/usr/bin/env node
import fs from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Codex runs shell commands in a sandbox with no sockets and no writes
// outside the workspace. An allow rule for the skill's scripts, in a file
// of the skill's own, runs them outside the sandbox without a prompt.
const skill = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const rulesFile = path.join(codexHome, "rules", "interactive-plan.rules");
const rules =
  ["scripts/session.mjs", "scripts/build.mjs", "scripts/check.mjs"]
    .map(
      (script) =>
        `prefix_rule(pattern=["node", ${JSON.stringify(path.join(skill, script))}], decision="allow", justification="interactive-plan: the helper talks to its local hub and writes the session under the state directory")`,
    )
    .join("\n") + "\n";
const rulesPresent = () =>
  fs
    .readFile(rulesFile, "utf8")
    .then((text) => text === rules)
    .catch(() => false);
if (process.argv[2] === "--codex-rules") {
  try {
    await fs.mkdir(path.dirname(rulesFile), { recursive: true });
    await fs.writeFile(rulesFile, rules, { mode: 0o600 });
  } catch (error) {
    console.error(
      error.code === "EPERM" && process.env.CODEX_SANDBOX
        ? `writing ${rulesFile} is itself outside the sandbox: run this command escalated, once`
        : error.message,
    );
    process.exit(1);
  }
  console.log(JSON.stringify({ rules: rulesFile, written: true }, null, 2));
  process.exit(0);
}
const codex =
  Boolean(process.env.CODEX_SANDBOX) ||
  (await fs.stat(codexHome).then(
    () => true,
    () => false,
  ));

let directory;
const server = http.createServer((_, response) => response.end("ready"));
const listen = (instance, port) =>
  new Promise((resolve, reject) => {
    instance.once("error", reject);
    instance.listen(port, "127.0.0.1", resolve);
  });
async function portReport(port) {
  const busy = await new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
  if (!busy) return { port, state: "free" };
  try {
    const response = await fetch(`http://127.0.0.1:${port}/api/hub`, {
      signal: AbortSignal.timeout(2000),
    });
    const info = await response.json();
    if (info.hub === true)
      return { port, state: "hub", version: info.version, live: info.live };
  } catch {
    /* Something other than a hub answers on the port. */
  }
  return { port, state: "busy" };
}
try {
  if (Number(process.versions.node.split(".")[0]) < 20)
    throw new Error("Node 20 or newer is required");
  const base = path.resolve(
    process.argv[2] ||
      process.env.XDG_STATE_HOME ||
      path.join(os.homedir(), ".local", "state"),
  );
  await fs.mkdir(base, { recursive: true });
  directory = await fs.mkdtemp(path.join(base, "plan-capability-"));
  await fs.writeFile(path.join(directory, "draft"), "ready");
  await fs.rename(path.join(directory, "draft"), path.join(directory, "saved"));
  if ((await fs.readFile(path.join(directory, "saved"), "utf8")) !== "ready")
    throw new Error("Session storage did not preserve the file");
  await listen(server, 0);
  const response = await fetch(`http://127.0.0.1:${server.address().port}`, {
    signal: AbortSignal.timeout(5000),
  });
  if ((await response.text()) !== "ready")
    throw new Error("Loopback request failed");
  const port =
    process.env.INTERACTIVE_PLAN_PORT === undefined
      ? 4747
      : Number(process.env.INTERACTIVE_PLAN_PORT);
  console.log(
    JSON.stringify(
      {
        ready: true,
        node: process.versions.node,
        platform: process.platform,
        storage: base,
        hub: port ? await portReport(port) : { port, state: "os-assigned" },
        browser: "Check available agent tools or ask for manual browser review",
        renderers: "Check required renderers in the actual browser",
        ...(codex
          ? {
              codex: {
                rules: rulesFile,
                present: await rulesPresent(),
                write: "node scripts/check.mjs --codex-rules",
              },
            }
          : {}),
      },
      null,
      2,
    ),
  );
} catch (error) {
  if (error.code === "EPERM" && process.env.CODEX_SANDBOX)
    console.error(
      `the Codex sandbox blocks the hub's socket and its state directory. Run outside the sandbox (escalated): node scripts/check.mjs --codex-rules, which writes ${rulesFile} so no later command asks. Then run the check again.`,
    );
  else console.error(error.message);
  process.exitCode = 1;
} finally {
  server.closeAllConnections();
  if (server.listening) await new Promise((resolve) => server.close(resolve));
  if (directory) await fs.rm(directory, { recursive: true, force: true });
}
