import assert from "node:assert/strict";
import { test } from "node:test";

import { controlRefreshKind } from "../src/refresh-policy.js";

test("navigation events use the lightweight refresh", () => {
  assert.equal(controlRefreshKind("%client-session-changed"), "navigation");
  assert.equal(controlRefreshKind("%session-window-changed"), "navigation");
  assert.equal(controlRefreshKind("%window-pane-changed"), "navigation");
});

test("structural events retain the full refresh", () => {
  for (const event of ["%layout-change", "%window-add", "%client-attached"]) {
    assert.equal(controlRefreshKind(event), "full", event);
  }
});

test("unrelated control notifications do not refresh", () => {
  assert.equal(controlRefreshKind("%output"), "ignore");
  assert.equal(controlRefreshKind("%message"), "ignore");
});
