import assert from "node:assert/strict";
import test from "node:test";
import {
  agentListening,
  defaultPage,
  neighbors,
  statusLine,
  stepperPills,
  threadRows,
} from "../../ai-harness/skills/visual-review/assets/outline.mjs";

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
    {
      id: "q3",
      title: "Export",
      text: "How does export embed the repository?",
      status: "asked",
      statusLine: null,
      followUps: [],
      pages: [],
    },
  ],
};

test("gives each stepper pill the facts that are true of its page", () => {
  const pills = stepperPills(answering, {
    questionId: "q1",
    pageId: "lifecycle",
  });
  assert.deepEqual(
    pills.map(
      (pill) =>
        `${pill.n}:${pill.id}${pill.written ? " written" : ""}${pill.current ? " current" : ""}` +
        `${pill.writing ? " writing" : ""}${pill.updated ? " updated" : ""}`,
    ),
    [
      "1:overview written",
      "2:lifecycle written current updated",
      "3:retries writing",
      "4:start",
    ],
    "only the first unwritten page is the one being written",
  );
  assert.deepEqual(
    stepperPills(answering, { questionId: "q3" }),
    [],
    "no pages, no pills",
  );
  assert.deepEqual(stepperPills(answering, {}), []);
});

test("reads a question's status line for the thread", () => {
  assert.equal(
    statusLine(answering.questions[0]),
    "4 pages · writing · reading 14 files",
  );
  assert.equal(statusLine(answering.questions[1]), "1 page");
  assert.equal(statusLine(answering.questions[2]), "asked");
  assert.equal(
    statusLine({ status: "planned", pages: [], statusLine: null }),
    "planning",
  );
});

const now = Date.parse("2026-09-18T10:00:00Z");
const listening = { ...answering, agentSeenAt: "2026-09-18T09:57:00Z" };

test("lists the thread in the order the questions were asked", () => {
  const rows = threadRows(listening, { questionId: "q2" }, now);
  assert.deepEqual(
    rows.map(
      (row) =>
        `${row.id}:${row.current ? "current" : ""}:${row.working ? "working" : "done"}:${row.firstPage}`,
    ),
    ["q1::working:overview", "q2:current:done:callers", "q3::working:null"],
  );
  assert.equal(rows[0].text, "How does a charge reach the ledger?");
});

test("says when no agent is listening, and expects none in an export", () => {
  assert.equal(agentListening(listening, now), true);
  const silent = { ...answering, agentSeenAt: "2026-09-18T09:54:59Z" };
  assert.equal(agentListening(silent, now), false, "five minutes of silence");
  assert.equal(agentListening(answering, now), false, "never heard from");

  const rows = threadRows(silent, {}, now);
  assert.deepEqual(
    rows.map((row) => `${row.id}:${row.line}:${row.working}`),
    [
      "q1:no agent listening:false",
      "q2:1 page:false",
      "q3:no agent listening:false",
    ],
    "unfinished questions say so; a finished one keeps its line",
  );
  assert.deepEqual(
    threadRows(silent, {}, null).map((row) => row.line),
    threadRows(listening, {}, now).map((row) => row.line),
    "an export has no agent and does not say so",
  );
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
    null,
    "the most recent question has no written page yet",
  );
  assert.deepEqual(defaultPage(answering, "q2"), {
    questionId: "q2",
    pageId: "callers",
  });
  assert.equal(defaultPage({ questions: [] }), null);
});
