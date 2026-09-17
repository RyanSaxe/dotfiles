import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultPage,
  neighbors,
  outlineModel,
  progressFor,
} from "../../ai-harness/skills/visual-review/assets/outline.mjs";
import { flattenTree } from "../../ai-harness/skills/visual-review/assets/code.mjs";

const answering = {
  stage: "working",
  questions: [
    {
      id: "q1",
      title: "Payments architecture",
      text: "How does a charge reach the ledger?",
      status: "writing",
      statusLine: "reading 14 files",
      followUps: [],
      pages: [
        {
          id: "overview",
          title: "Overview map",
          status: "written",
          revision: 1,
        },
        {
          id: "lifecycle",
          title: "Request lifecycle",
          status: "written",
          revision: 2,
        },
        { id: "retries", title: "Retries", status: "planned" },
        { id: "start", title: "Where to start", status: "planned" },
      ],
    },
    {
      id: "q2",
      title: "Ledger callers",
      text: "Who writes to the ledger?",
      status: "done",
      statusLine: null,
      followUps: [{ id: "f1" }],
      pages: [
        { id: "callers", title: "Callers", status: "written", revision: 1 },
      ],
    },
  ],
};

test("describes each page by what is true of it", () => {
  const model = outlineModel(answering, {
    questionId: "q1",
    pageId: "lifecycle",
  });
  assert.deepEqual(
    model.questions[0].pages.map(
      (page) =>
        `${page.id}${page.written ? " written" : ""}${page.current ? " current" : ""}` +
        `${page.writing ? " writing" : ""}${page.updated ? " updated" : ""}`,
    ),
    [
      "overview written",
      "lifecycle written current updated",
      "retries writing",
      "start",
    ],
    "only the first unwritten page is the one being written",
  );
  assert.equal(model.questions[0].pageCount, 4);
  assert.equal(model.questions[0].writtenCount, 2);
  assert.equal(model.questions[1].followUpCount, 1);
});

test("keeps questions in the order they were asked and collapses on request", () => {
  const model = outlineModel(answering, {
    questionId: "q1",
    collapsed: new Set(["q2"]),
  });
  assert.deepEqual(
    model.questions.map((question) => question.id),
    ["q1", "q2"],
  );
  assert.equal(model.questions[1].expanded, false);
  assert.deepEqual(
    model.questions[1].pages,
    [],
    "a collapsed question lists no pages",
  );
  assert.equal(
    model.questions[1].pageCount,
    1,
    "a collapsed question still reports how many pages it has",
  );
});

test("reports progress for the question still being answered", () => {
  const progress = progressFor(answering, "q1");
  assert.equal(progress.questionId, "q1");
  assert.equal(progress.written, 2);
  assert.equal(progress.total, 4);
  assert.equal(progress.fraction, 0.5);
  assert.equal(progress.label, "Writing Retries · 3 of 4");
  assert.equal(progress.statusLine, "reading 14 files");
});

test("reports nothing to wait on once every answer is finished", () => {
  const finished = {
    questions: answering.questions.map((question) => ({
      ...question,
      status: "done",
    })),
  };
  assert.equal(progressFor(finished), null);
  assert.equal(outlineModel(finished).progress, null);
});

test("says Planning before the outline exists", () => {
  const asked = {
    questions: [
      { id: "q", title: "?", status: "asked", pages: [], followUps: [] },
    ],
  };
  assert.equal(progressFor(asked).label, "Planning");
  assert.equal(progressFor(asked).fraction, 0);
});

test("moves between written pages only", () => {
  const middle = neighbors(answering, "q1", "lifecycle");
  assert.equal(middle.previous.id, "overview");
  assert.equal(
    middle.next,
    null,
    "a planned page is not somewhere the reader can go",
  );
  assert.equal(middle.index, 1);
  assert.equal(middle.pages.length, 2);

  const first = neighbors(answering, "q1", "overview");
  assert.equal(first.previous, null);
  assert.equal(first.next.id, "lifecycle");
});

test("falls back to a page that exists", () => {
  assert.deepEqual(defaultPage(answering, "q1"), {
    questionId: "q1",
    pageId: "overview",
  });
  assert.deepEqual(
    defaultPage(answering, "missing"),
    { questionId: "q2", pageId: "callers" },
    "an unknown question falls back to the most recent one",
  );
  assert.equal(defaultPage({ questions: [] }), null);
});

test("expands the file tree one directory at a time", async () => {
  const tree = {
    "": [
      { name: "src", type: "directory" },
      { name: "tests", type: "directory" },
      { name: "README.md", type: "file" },
    ],
    src: [
      { name: "ledger", type: "directory" },
      { name: "client.py", type: "file" },
    ],
    "src/ledger": [{ name: "writer.py", type: "file" }],
    tests: [{ name: "test_client.py", type: "file" }],
  };
  const asked = [];
  const read = async (directory) => {
    asked.push(directory);
    return tree[directory] ?? [];
  };

  const closed = await flattenTree(read, new Set());
  assert.deepEqual(
    asked,
    [""],
    "a closed tree reads the root and nothing else",
  );
  assert.deepEqual(
    closed.map((row) => `${row.depth}:${row.path}`),
    ["0:src", "0:tests", "0:README.md"],
  );

  asked.length = 0;
  const open = await flattenTree(read, new Set(["src", "src/ledger"]));
  assert.deepEqual(
    asked,
    ["", "src", "src/ledger"],
    "one read per open directory, and none for directories left closed",
  );
  assert.deepEqual(
    open.map((row) => `${row.depth}:${row.path}`),
    [
      "0:src",
      "1:src/ledger",
      "2:src/ledger/writer.py",
      "1:src/client.py",
      "0:tests",
      "0:README.md",
    ],
  );
});
