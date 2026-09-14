#!/usr/bin/env node
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

let directory;
const server = http.createServer((_, response) => response.end("ready"));
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
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const response = await fetch(`http://127.0.0.1:${server.address().port}`, {
    signal: AbortSignal.timeout(5000),
  });
  if ((await response.text()) !== "ready")
    throw new Error("Loopback request failed");
  console.log(
    JSON.stringify(
      {
        ready: true,
        node: process.versions.node,
        platform: process.platform,
        storage: base,
        browser: "Check available agent tools or ask for manual browser review",
        renderers: "Check required renderers in the actual browser",
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  server.closeAllConnections();
  if (server.listening) await new Promise((resolve) => server.close(resolve));
  if (directory) await fs.rm(directory, { recursive: true, force: true });
}
