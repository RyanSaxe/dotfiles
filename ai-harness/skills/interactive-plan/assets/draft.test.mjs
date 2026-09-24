import assert from "node:assert/strict";
import { test } from "node:test";
import {
  emptyDraft,
  loadDraft,
  markSent,
  submissionGroups,
  unsentItems,
} from "./draft.mjs";

const list = (label, touched = false) => ({
  kind: "multiple",
  topic: "scope",
  label,
  target: "multiselect-scope-0",
  revision: "1",
  touched,
  options: [{ value: "a", label: "A", checked: true }],
});
const draftWith = (choices) => ({ ...emptyDraft("1"), choices });

test("alignment defaults on, preserves a changed value, and travels with feedback", () => {
  const fresh = emptyDraft("1");
  assert.equal(fresh.alignUnflagged, true);
  assert.equal(submissionGroups(fresh).alignUnflagged, true);
  fresh.alignUnflagged = false;
  assert.equal(submissionGroups(fresh).alignUnflagged, false);
  assert.equal(loadDraft(fresh, "2").alignUnflagged, false);
  const older = { ...fresh };
  delete older.alignUnflagged;
  assert.equal(loadDraft(older, "2").alignUnflagged, true);
});

test("an untouched checklist does not count", () => {
  const draft = draftWith({
    "scope/one": list("One"),
    "scope/two": list("Two"),
  });
  assert.equal(unsentItems(draft).count, 0);
  assert.deepEqual(Object.keys(submissionGroups(draft).choices), [
    "scope/one",
    "scope/two",
  ]);
});

test("a touched checklist counts once, even when put back", () => {
  const draft = draftWith({
    "scope/one": list("One", true),
    "scope/two": list("Two"),
  });
  assert.equal(unsentItems(draft).count, 1);
  assert.equal(submissionGroups(draft).choices["scope/one"].touched, true);
  assert.equal(submissionGroups(draft).choices["scope/two"].touched, false);
  assert.equal(
    unsentItems(draftWith({ "scope/one": list("One", true) })).count,
    1,
  );
});

test("a submit sends every list and the next revision starts them fresh", () => {
  const draft = draftWith({
    "scope/one": list("One", true),
    "scope/two": list("Two"),
  });
  markSent(draft, "evt", "2026-09-18T00:00:00Z");
  assert.equal(draft.submitted.count, 1);
  assert.equal(draft.choices["scope/two"].sentIn, "evt");
  assert.equal(unsentItems(draft).count, 0);
  const next = loadDraft(JSON.parse(JSON.stringify(draft)), "2");
  assert.deepEqual(next.choices, {});
});

test("a touched, unsent list carries over to the next revision", () => {
  const draft = draftWith({ "scope/one": list("One", true) });
  const next = loadDraft(JSON.parse(JSON.stringify(draft)), "2");
  assert.equal(next.choices["scope/one"].touched, true);
  assert.equal(unsentItems(next).count, 1);
});

test("single choices count as before", () => {
  const draft = draftWith({
    "d/pick": {
      topic: "d",
      label: "Pick",
      value: "x",
      valueLabel: "X",
      target: "t",
      revision: "1",
    },
  });
  assert.equal(unsentItems(draft).count, 1);
});
