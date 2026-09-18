import assert from "node:assert/strict";
import test from "node:test";
import {
  enclosingSymbol,
  foldWindow,
} from "../../ai-harness/skills/visual-review/assets/code.mjs";

test("opens a window around the cited lines and clips it to the file", () => {
  assert.deepEqual(foldWindow(345, 357, 773), { from: 337, to: 365 });
  assert.deepEqual(
    foldWindow(3, 3, 773),
    { from: 1, to: 11 },
    "the top of the file",
  );
  assert.deepEqual(
    foldWindow(770, 773, 773),
    { from: 762, to: 773 },
    "the bottom",
  );
  assert.deepEqual(
    foldWindow(5, 2, 10),
    { from: 1, to: 10 },
    "a backwards range widens to the start",
  );
  assert.deepEqual(
    foldWindow(null, null, 20000),
    { from: 1, to: 400 },
    "no citation opens the top",
  );
  assert.deepEqual(foldWindow(null, null, 12), { from: 1, to: 12 });
});

test("names the definition a fold hides", () => {
  const lines = [
    "import x from 'y';",
    "",
    "export async function submit(data) {",
    "  requireValue(data);",
    "  if (data.intent === 'accept-plan') {",
    "    check();",
    "  }",
    "}",
    "const later = () => {",
    "  return 1;",
    "};",
    "class Ledger",
    "  append() {}",
    "}",
    "def charge",
    "    pass",
  ];
  assert.equal(enclosingSymbol(lines, 5), "function submit");
  assert.equal(enclosingSymbol(lines, 9), "const later");
  assert.equal(enclosingSymbol(lines, 12), "class Ledger");
  assert.equal(enclosingSymbol(lines, 15), "def charge");
  assert.equal(
    enclosingSymbol(lines, 1),
    null,
    "nothing above the first definition",
  );
  assert.equal(enclosingSymbol([], 0), null);
  const long = ["function " + "a".repeat(80) + "() {"];
  assert.equal(enclosingSymbol(long, 1).length, 48);
});
