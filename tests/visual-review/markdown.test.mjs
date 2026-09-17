import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  blockNames,
  formatLocation,
  looksLikePath,
  parseBlock,
  parseCompare,
  parseLocation,
  parseRange,
  parseTarget,
  sanitizerConfig,
  targetKey,
} from "../../ai-harness/skills/visual-review/assets/grammar.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));

test("reads every form of the location grammar", () => {
  assert.deepEqual(parseLocation("src/client.py"), {
    path: "src/client.py",
    ref: null,
    start: null,
    end: null,
  });
  assert.deepEqual(parseLocation("src/client.py:42"), {
    path: "src/client.py",
    ref: null,
    start: 42,
    end: 42,
  });
  assert.deepEqual(parseLocation("src/client.py:42-48"), {
    path: "src/client.py",
    ref: null,
    start: 42,
    end: 48,
  });
  assert.deepEqual(parseLocation("src/client.py@main:42"), {
    path: "src/client.py",
    ref: "main",
    start: 42,
    end: 42,
  });
  assert.equal(parseLocation("src/client.py@pr/123:7").ref, "pr/123");
  assert.equal(
    parseLocation("weird@name.py@main:1").path,
    "weird@name.py",
    "the ref is taken from the last @, so a path may contain one",
  );
});

test("refuses locations that are not locations", () => {
  for (const input of [
    "",
    "   ",
    "/etc/passwd",
    "-rf",
    "../secrets.env",
    "./src/a.py",
    "src\\client.py",
    "src/client.py:0",
    "src/client.py:9-2",
    "src/client.py@:3",
    "src/client.py@bad ref:3",
    "two words.py",
  ])
    assert.equal(parseLocation(input), null, `${input} should not parse`);
});

test("formats a location the way chips and copies show it", () => {
  assert.equal(formatLocation(parseLocation("a/b.py@main:3-9")), "a/b.py:3-9");
  assert.equal(formatLocation(parseLocation("a/b.py:3")), "a/b.py:3");
  assert.equal(formatLocation(parseLocation("a/b.py")), "a/b.py");
  assert.equal(formatLocation(null), "");
});

test("treats only code that could name a file as a reference", () => {
  assert.ok(looksLikePath("src/client.py"));
  assert.ok(looksLikePath("README.md"));
  assert.ok(looksLikePath("src/client.py:42"));
  for (const input of ["charge()", "MAX_ATTEMPTS", "RetryableError", "n"])
    assert.equal(looksLikePath(input), null, `${input} is prose, not a path`);
});

test("reads note ranges for files and for sides of a diff", () => {
  assert.deepEqual(parseRange("42"), { start: 42, end: 42, side: null });
  assert.deepEqual(parseRange("42-48"), { start: 42, end: 48, side: null });
  assert.deepEqual(parseRange("+8"), { start: 8, end: 8, side: "additions" });
  assert.deepEqual(parseRange("-14"), {
    start: 14,
    end: 14,
    side: "deletions",
  });
  for (const input of ["", "abc", "0", "9-2", "+", "1-"])
    assert.equal(parseRange(input), null, `${input} is not a range`);
});

test("reads a note target and keys it the same way every page does", () => {
  assert.deepEqual(parseTarget("src/client.py@main"), {
    kind: "file",
    path: "src/client.py",
    ref: "main",
  });
  assert.deepEqual(parseTarget("main..pr/7 src/client.py"), {
    kind: "diff",
    base: "main",
    head: "pr/7",
    path: "src/client.py",
  });
  assert.equal(
    parseTarget("src/client.py@main:3"),
    null,
    "a target has no lines",
  );
  assert.equal(
    targetKey(parseTarget("main..pr/7 src/client.py")),
    "main..pr/7 src/client.py",
  );
  assert.equal(
    targetKey(parseTarget("src/client.py@main")),
    "src/client.py@main",
  );
});

test("dispatches every block the grammar names", () => {
  assert.deepEqual(blockNames.sort(), [
    "chart",
    "choose",
    "code",
    "diff",
    "mermaid",
    "notes",
    "steps",
  ]);

  assert.equal(
    parseBlock("mermaid", "flowchart LR\n a --> b\n").data.source,
    "flowchart LR\n a --> b",
  );

  const excerpt = parseBlock(
    "code src/client.py@main:42-48",
    "42  The loop.\n46  Backoff doubles from 0.5s,\n    capped at 30s.\n",
  );
  assert.equal(excerpt.data.location.start, 42);
  assert.deepEqual(excerpt.data.notes, [
    { line: 42, text: "The loop." },
    { line: 46, text: "Backoff doubles from 0.5s, capped at 30s." },
  ]);

  const diff = parseBlock(
    "diff main..pr/123 src/client.py",
    "Why it changed.\n",
  );
  assert.deepEqual(diff.data, {
    kind: "diff",
    base: "main",
    head: "pr/123",
    path: "src/client.py",
    prose: "Why it changed.",
  });

  const steps = parseBlock(
    "steps",
    "1. src/a.py@main:5\n   First.\n2. src/b.py:9\n   Second.\n",
  );
  assert.equal(steps.data.steps.length, 2);
  assert.equal(steps.data.steps[1].location.path, "src/b.py");
  assert.equal(steps.data.steps[0].text, "First.");

  const choice = parseBlock("choose Where next?", "- One\n- Two\n- Three\n");
  assert.equal(choice.data.title, "Where next?");
  assert.equal(choice.data.options.length, 3);

  const chart = parseBlock(
    "chart Backoff",
    '{"type":"bar","x":[1,2],"y":[0.5,1],"unit":"seconds"}',
  );
  assert.equal(chart.data.chart.type, "bar");
  assert.equal(chart.data.title, "Backoff");

  const notes = parseBlock(
    "notes main..pr/7 src/client.py",
    "+8   Runs before the loop.\n-14  Used to reach the gateway.\n",
  );
  assert.equal(notes.data.key, "main..pr/7 src/client.py");
  assert.deepEqual(notes.data.notes[0], {
    start: 8,
    end: 8,
    side: "additions",
    text: "Runs before the loop.",
  });
});

test("keeps an unreadable block on the page with the reason", () => {
  const unknown = parseBlock("filetree src", "anything");
  assert.equal(unknown.data, undefined);
  assert.match(unknown.error, /No block named filetree/);
  assert.equal(unknown.source, "anything", "the source survives to be shown");

  const cases = [
    ["code src/a.py", "a code excerpt with no lines"],
    ["code not a path:1", "a code excerpt with no path"],
    ["diff src/a.py", "a diff with no refs"],
    ["steps", "a walkthrough with no steps"],
    ["choose Only one", "- One\n"],
    ["choose Too many", "- 1\n- 2\n- 3\n- 4\n- 5\n"],
    ["chart X", "not json"],
    ["chart X", '{"type":"pie","x":[1],"y":[1]}'],
    ["chart X", '{"type":"bar","x":[1,2],"y":[1]}'],
    ["notes src/a.py@main:3", "1  note"],
    ["notes src/a.py@main", "+1  a side range on a file"],
    ["notes src/a.py@main", "nonsense"],
  ];
  for (const [info, body] of cases) {
    const block = parseBlock(info, body);
    assert.ok(block.error, `${info} / ${body} should carry an error`);
    assert.equal(block.data, undefined);
  }
});

test("names the two sides of a comparison", () => {
  assert.deepEqual(parseCompare("Before | After PR #123"), {
    before: "Before",
    after: "After PR #123",
  });
  assert.deepEqual(parseCompare(""), { before: "Before", after: "After" });
});

test("forbids the HTML that would let a page act on its own", () => {
  for (const tag of ["script", "iframe", "form", "object", "embed"])
    assert.ok(
      sanitizerConfig.FORBID_TAGS.includes(tag),
      `${tag} must be forbidden`,
    );
  assert.equal(
    sanitizerConfig.ALLOW_DATA_ATTR,
    false,
    "data attributes carry the page's own mount points; agent HTML may not set them",
  );
});

test("every fixture page parses with no unknown blocks", async () => {
  const directory = path.join(here, "fixtures/pages");
  const names = await fs.readdir(directory);
  assert.ok(names.length >= 5);
  const seen = new Set();
  for (const name of names) {
    const source = await fs.readFile(path.join(directory, name), "utf8");
    for (const match of source.matchAll(/^```([^\n`]*)\n([\s\S]*?)^```$/gm)) {
      const block = parseBlock(match[1], match[2]);
      assert.equal(block.error, undefined, `${name}: ${block.error}`);
      seen.add(block.name);
    }
  }
  assert.deepEqual(
    [...seen].sort(),
    ["chart", "choose", "code", "diff", "mermaid", "notes", "steps"],
    "the fixtures exercise every block",
  );
});
