// Checks the shared tab registry and the fixed-width tab bar contract.

import assert from "node:assert/strict";

import { loadRailTab, RAIL_TABS } from "../src/tabs.js";
import { tabBar } from "../src/sections/header.js";
import { loadPalette } from "../src/theme.js";

assert.deepEqual(
  RAIL_TABS.map((tab) => [tab.id, tab.label, tab.elementAction]),
  [
    ["agents", "Agents", "agent_jump"],
    ["reviews", "Reviews", "review_open"],
    ["tasks", "Tasks", "task_jump"],
  ],
);

const palette = loadPalette();
const attention = { agents: true, reviews: false, tasks: false };
const rendered = tabBar("tasks", attention, palette, 26);
assert.match(rendered, /Agents/);
assert.match(rendered, /Reviews/);
assert.match(rendered, /Tasks/);
assert.equal(loadRailTab("/tmp/rail-tab-does-not-exist"), "agents");

console.log("tab checks passed");
