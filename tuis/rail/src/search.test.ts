import assert from "node:assert/strict";
import { test } from "node:test";

import { rank, scoreFields, scoreTerm } from "./search.js";

// The bug this module exists to fix: the old filter tested whether a query
// was a subsequence of every field joined together, so `/asdf` matched all
// four live review rows.
const ROW = [
  "buffergolf.nvim",
  "#4",
  "CI",
  "CI red",
  "290d",
  "Test PR 2: Add return value documentation",
];

test("a query that matches no single field is rejected", () => {
  assert.equal(scoreFields(ROW, "asdf"), null);
  assert.equal(scoreFields(ROW, "aeiou"), null);
  assert.equal(scoreFields(ROW, "dotfiles"), null);
});

test("a query inside one field matches", () => {
  assert.notEqual(scoreFields(ROW, "buffergolf"), null);
  assert.notEqual(scoreFields(ROW, "return value"), null);
});

test("an intact substring outranks a scattered subsequence", () => {
  const intact = scoreTerm("lint", "lint");
  const scattered = scoreTerm("look at the lint rule", "lint");
  assert.ok(intact !== null && scattered !== null);
  assert.ok(intact.score > scattered.score);
});

test("a word-start match outranks one mid-word", () => {
  const start = scoreTerm("lint failed", "lint");
  const middle = scoreTerm("prelint failed", "lint");
  assert.ok(start !== null && middle !== null);
  assert.ok(start.score > middle.score);
});

test("positions mark the characters that matched", () => {
  const match = scoreTerm("buffergolf.nvim", "golf");
  assert.deepEqual(match?.positions, [6, 7, 8, 9]);
});

test("subsequence still matches when nothing is contiguous", () => {
  const match = scoreTerm("Capitalize Vim in README", "cvr");
  assert.ok(match !== null);
  assert.equal(match.positions.length, 3);
});

test("every whitespace term must match some field", () => {
  assert.notEqual(scoreFields(ROW, "buffergolf ci"), null);
  assert.equal(scoreFields(ROW, "buffergolf nope"), null);
});

test("terms may match different fields", () => {
  const match = scoreFields(ROW, "nvim 290d");
  assert.ok(match !== null);
  assert.deepEqual([...match.hits.keys()].sort(), [0, 4]);
});

test("rank sorts best first and drops non-matches", () => {
  const items = [
    { fields: ["look at the lint rule"] },
    { fields: ["lint"] },
    { fields: ["nothing here"] },
  ];
  const ranked = rank(items, "lint", (item) => item.fields);
  assert.equal(ranked.length, 2);
  assert.deepEqual(ranked[0]?.item.fields, ["lint"]);
});

test("an empty query keeps every item in its original order", () => {
  const items = [{ fields: ["b"] }, { fields: ["a"] }];
  const ranked = rank(items, "   ", (item) => item.fields);
  assert.deepEqual(
    ranked.map((entry) => entry.item.fields[0]),
    ["b", "a"],
  );
});
