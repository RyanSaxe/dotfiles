// The build contract behind `node dist/*.mjs`: every entrypoint bundles, and
// a bundle only ever runs its OWN program. tab-element inlines
// review-dashboard, whose argv[1] === import.meta.url entry guard would fire
// inside the tab-element bundle without the basename pin — printing another
// program's usage and exiting 1 into a tmux run-shell overlay.

import assert from "node:assert/strict";
import { test } from "node:test";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const RAIL = join(fileURLToPath(import.meta.url), "..", "..");
const DIST = join(RAIL, "dist");
const ENTRIES = [
  "daemon.mjs",
  "review-dashboard.mjs",
  "tab-element.mjs",
  "jump-attention.mjs",
  join("attention", "cli.mjs"),
];

// One real build for the whole file; the entry list lives in package.json.
execFileSync("npm", ["run", "--silent", "build"], { cwd: RAIL, stdio: "pipe" });

// Bundles never see the real machine: no PATH tools (tmux, gh), scratch
// state, no TMUX. Anything they would exec is absent, so a probe that
// still exits cleanly proves the bundle itself is sound.
const isolated = {
  ...process.env,
  PATH: "/usr/bin:/bin",
  XDG_STATE_HOME: mkdtempSync(join(tmpdir(), "rail-build-test-")),
  TMUX: undefined,
  TMUX_PANE: undefined,
};

test("build emits every entrypoint plus the stamp", () => {
  for (const entry of ENTRIES) {
    assert.ok(existsSync(join(DIST, entry)), `missing dist/${entry}`);
  }
  assert.ok(existsSync(join(DIST, ".stamp")), "missing dist/.stamp");
});

test("every bundle parses as an ES module", () => {
  for (const entry of ENTRIES) {
    const result = spawnSync(process.execPath, ["--check", join(DIST, entry)], {
      encoding: "utf8",
    });
    assert.equal(
      result.status,
      0,
      `node --check dist/${entry}: ${result.stderr}`,
    );
  }
});

test("review-dashboard's own bundle runs its entry guard", () => {
  const result = spawnSync(
    process.execPath,
    [join(DIST, "review-dashboard.mjs"), "bogus"],
    { encoding: "utf8", env: isolated },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /usage: review-dashboard reviews\|tasks/);
});

test("tab-element's bundle never fires the inlined review-dashboard guard", () => {
  // Invalid element digit: tab-element's own miss contract is a silent
  // clean exit (the tmux display-message it attempts is absent here and
  // swallowed by design).
  const result = spawnSync(
    process.execPath,
    [join(DIST, "tab-element.mjs"), "0"],
    { encoding: "utf8", env: isolated },
  );
  assert.equal(result.status, 0, `stderr: ${result.stderr}`);
  assert.doesNotMatch(result.stderr, /review-dashboard/);
  assert.doesNotMatch(result.stdout, /review-dashboard/);
});
