#!/usr/bin/env node
// Wakes a Copilot CLI session through the SDK shipped inside the CLI: connect
// to the TUI's embedded server, resume the session, and enqueue one prompt.
// The hub runs this as a child process so a broken SDK cannot take it down.
import { pathToFileURL } from "node:url";

const [sdk, port, sessionId, line] = process.argv.slice(2);
if (!sdk || !port || !sessionId || !line) {
  console.error("Usage: wake-copilot.mjs SDK PORT SESSION_ID LINE");
  process.exit(1);
}
const { CopilotClient, approveAll } = await import(pathToFileURL(sdk).href);
const client = new CopilotClient({
  connection: { kind: "uri", url: `http://127.0.0.1:${port}` },
  logLevel: "error",
});
await client.start();
try {
  const session = await client.resumeSession(sessionId, {
    onPermissionRequest: approveAll,
  });
  await session.send({ prompt: line, mode: "enqueue" });
} finally {
  await client.stop();
}
