// Concurrent tmux hooks may all request startup. The launcher must let the
// kernel choose one daemon, and the lock must become available after a crash.

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const RAIL = join(fileURLToPath(import.meta.url), "..", "..");
const RAIL_BIN = join(RAIL, "bin", "rail");
const hasLockUtility =
  spawnSync("sh", [
    "-c",
    "command -v lockf >/dev/null 2>&1 || command -v flock >/dev/null 2>&1",
  ]).status === 0;

const pidsIn = (path: string): number[] =>
  existsSync(path)
    ? readFileSync(path, "utf8").trim().split("\n").filter(Boolean).map(Number)
    : [];

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

async function waitFor(
  condition: () => boolean,
  description: string,
): Promise<void> {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (condition()) return;
    await sleep(25);
  }
  assert.fail(`timed out waiting for ${description}`);
}

function railEnsure(env: NodeJS.ProcessEnv): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(RAIL_BIN, ["ensure-daemon"], {
      env,
      stdio: "ignore",
    });
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`rail ensure-daemon exited ${String(code)}`));
    });
  });
}

function pidIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ESRCH") return false;
    throw error;
  }
}

test("daemon refuses to start without the launcher's held lock", () => {
  const xdgStateHome = mkdtempSync(join(tmpdir(), "rail-unlocked-daemon-"));
  const env = { ...process.env };
  delete env.RAIL_DAEMON_LOCKED;

  try {
    const result = spawnSync(
      process.execPath,
      ["--import", "tsx", "src/daemon.ts"],
      {
        cwd: RAIL,
        env: { ...env, XDG_STATE_HOME: xdgStateHome },
        encoding: "utf8",
        timeout: 5000,
      },
    );

    assert.equal(result.status, 1);
    assert.match(result.stderr, /must start through `rail ensure-daemon`/);
  } finally {
    rmSync(xdgStateHome, { recursive: true, force: true });
  }
});

test(
  "concurrent ensure-daemon calls start one owner and recover after a crash",
  { skip: !hasLockUtility },
  async () => {
    const temp = mkdtempSync(join(tmpdir(), "rail-daemon-lock-"));
    const fixture = join(temp, "fixture");
    const railDir = join(fixture, "tuis", "rail");
    const dist = join(railDir, "dist");
    const stateHome = join(temp, "state");
    const starts = join(temp, "daemon-starts");
    const stateDir = join(stateHome, "dotfiles", "rail");
    const distEntry = join(dist, "daemon.mjs");
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      RAIL_DIR: railDir,
      REPO_ROOT: fixture,
      RAIL_STARTS: starts,
      XDG_STATE_HOME: stateHome,
    };
    const startedPids = new Set<number>();

    mkdirSync(join(railDir, "src"), { recursive: true });
    mkdirSync(dist, { recursive: true });
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(join(dist, ".stamp"), "built\n");
    writeFileSync(
      distEntry,
      [
        'import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";',
        'import { join } from "node:path";',
        'if (process.env.RAIL_DAEMON_LOCKED !== "1") process.exit(2);',
        'const state = join(process.env.XDG_STATE_HOME, "dotfiles", "rail");',
        "mkdirSync(state, { recursive: true });",
        'writeFileSync(join(state, "daemon.pid"), String(process.pid));',
        'appendFileSync(process.env.RAIL_STARTS, String(process.pid) + "\\n");',
        "setInterval(() => {}, 1000);",
        "",
      ].join("\n"),
    );
    writeFileSync(join(stateDir, "daemon.pid"), "99999999");

    try {
      await Promise.all(Array.from({ length: 12 }, () => railEnsure(env)));
      await waitFor(() => pidsIn(starts).length >= 1, "the first daemon");
      await sleep(250);

      const firstPids = pidsIn(starts);
      firstPids.forEach((pid) => startedPids.add(pid));
      assert.equal(firstPids.length, 1, "only one concurrent launcher may win");
      assert.equal(
        readFileSync(join(stateDir, "daemon.pid"), "utf8"),
        String(firstPids[0]),
        "daemon.pid reports the lock owner",
      );
      assert.ok(existsSync(join(stateDir, "daemon.lock")));

      process.kill(firstPids[0]!, "SIGKILL");
      await waitFor(
        () => !pidIsAlive(firstPids[0]!),
        "the killed daemon to exit",
      );

      await railEnsure(env);
      await waitFor(() => pidsIn(starts).length >= 2, "a replacement daemon");
      await sleep(250);

      const allPids = pidsIn(starts);
      allPids.forEach((pid) => startedPids.add(pid));
      assert.equal(allPids.length, 2, "the released lock permits one restart");
      assert.notEqual(allPids[1]!, allPids[0]!);
      assert.equal(
        readFileSync(join(stateDir, "daemon.pid"), "utf8"),
        String(allPids[1]),
        "the stale pidfile is overwritten by the replacement owner",
      );
    } finally {
      for (const pid of startedPids) {
        if (pidIsAlive(pid)) process.kill(pid, "SIGKILL");
      }
      await sleep(100);
      rmSync(temp, { recursive: true, force: true });
    }
  },
);
