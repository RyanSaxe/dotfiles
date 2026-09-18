import assert from "node:assert/strict";
import test from "node:test";
import { parseBlock } from "../../ai-harness/skills/visual-review/assets/grammar.mjs";
import { createNoteRegistry } from "../../ai-harness/skills/visual-review/assets/notes.mjs";

const from = (pageId, pageTitle) => ({
  questionId: "q1",
  pageId,
  questionTitle: "Payments",
  pageTitle,
});

test("collects notes from fences and from excerpt margins alike", () => {
  const registry = createNoteRegistry();
  registry.setPage("q1/overview", {
    notes: [
      parseBlock(
        "notes src/client.py@main",
        "42-48  The retry loop.\n46     Capped at 30s.\n",
      ).data,
    ],
    from: from("overview", "Overview"),
  });
  registry.setPage("q1/retries", {
    blocks: [
      parseBlock("code src/client.py@main:60-62", "61  The breaker check.\n"),
      parseBlock("mermaid", "flowchart LR\n a --> b\n"),
    ],
    from: from("retries", "Retries"),
  });

  const notes = registry.forTarget("src/client.py@main");
  assert.deepEqual(
    notes.map((note) => `${note.n}:${note.start}-${note.end}:${note.text}`),
    [
      "1:42-48:The retry loop.",
      "2:46-46:Capped at 30s.",
      "3:61-61:The breaker check.",
    ],
    "a margin note on an excerpt is a note on the file, numbered in line order",
  );
  assert.equal(notes[2].from.pageTitle, "Retries");
  assert.deepEqual(registry.targets(), ["src/client.py@main"]);
});

test("keeps a diff's notes separate from the file's", () => {
  const registry = createNoteRegistry();
  registry.setPage("q1/change", {
    notes: [
      parseBlock(
        "notes main..pr/7 src/client.py",
        "+8  Runs before the loop.\n",
      ).data,
      parseBlock("notes src/client.py@main", "8  The loop itself.\n").data,
    ],
    from: from("change", "What changed"),
  });

  const inDiff = registry.forTarget("main..pr/7 src/client.py");
  assert.equal(inDiff.length, 1);
  assert.equal(inDiff[0].side, "additions");

  const inFile = registry.forTarget("src/client.py@main");
  assert.equal(inFile.length, 1);
  assert.equal(inFile[0].side, null);
  assert.equal(
    inFile[0].n,
    1,
    "numbering runs per target, so each view counts from one",
  );
});

test("republishing a page replaces the notes it used to carry", () => {
  const registry = createNoteRegistry();
  registry.setPage("q1/overview", {
    notes: [parseBlock("notes a.py@main", "1  First.\n2  Second.\n").data],
    from: from("overview", "Overview"),
  });
  assert.equal(registry.forTarget("a.py@main").length, 2);

  registry.setPage("q1/overview", {
    notes: [parseBlock("notes a.py@main", "1  Rewritten.\n").data],
    from: from("overview", "Overview"),
  });
  const notes = registry.forTarget("a.py@main");
  assert.deepEqual(
    notes.map((note) => note.text),
    ["Rewritten."],
    "a rewritten page must not leave its old notes behind",
  );

  registry.setPage("q1/overview", {
    notes: [],
    from: from("overview", "Overview"),
  });
  assert.deepEqual(registry.forTarget("a.py@main"), []);
  assert.deepEqual(registry.targets(), []);
});

test("a target nobody annotated has no notes", () => {
  const registry = createNoteRegistry();
  registry.setPage("q1/overview", {
    notes: [parseBlock("notes a.py@main", "1  Only here.\n").data],
    from: from("overview", "Overview"),
  });
  assert.deepEqual(registry.forTarget("b.py@main"), []);
  assert.deepEqual(registry.forTarget("main..pr/7 a.py"), []);
});

test("merges notes several pages wrote about one file", () => {
  const registry = createNoteRegistry();
  registry.setPage("q1/a", {
    notes: [parseBlock("notes a.py@main", "9  From A.\n").data],
    from: from("a", "Page A"),
  });
  registry.setPage("q1/b", {
    notes: [parseBlock("notes a.py@main", "3  From B.\n").data],
    from: from("b", "Page B"),
  });
  const notes = registry.forTarget("a.py@main");
  assert.deepEqual(
    notes.map((note) => `${note.n}:${note.start}:${note.from.pageTitle}`),
    ["1:3:Page B", "2:9:Page A"],
    "order follows the file, not the order the pages were written",
  );
});
