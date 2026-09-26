import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";

const frame = await fs.readFile(new URL("./frame.js", import.meta.url), "utf8");

test("note highlights are cleared before page and dialog text changes", () => {
  const showStart = frame.indexOf("function show(");
  const notesStart = frame.indexOf("\n/* Notes on the text */", showStart);
  const show = frame.slice(showStart, notesStart);
  const openStart = frame.indexOf("function openNote(");
  const agreedStart = frame.indexOf("\n/* Agreed */", openStart);
  const open = frame.slice(openStart, agreedStart);

  const showClear = show.indexOf('clearHighlight("plan-note");');
  const pageReplacement = show.indexOf('$("page-content").innerHTML');
  assert.ok(showClear >= 0, "show clears the page's note highlight");
  assert.ok(showClear < pageReplacement);
  const openClear = open.indexOf('clearHighlight("plan-note");');
  const dialogText = open.indexOf('$("note-anchor").textContent');
  assert.ok(openClear >= 0, "openNote clears the dialog's note highlight");
  assert.ok(openClear < dialogText);
  const closeStart = frame.indexOf('$("note-dialog").addEventListener("close"');
  const close = frame.slice(closeStart, frame.indexOf("\n});", closeStart));
  assert.ok(close.includes('!$("note-dialog").open'));
  assert.ok(close.includes('!$("reading").hidden'));
  assert.ok(close.includes('page.id !== "agreed"'));
  assert.ok(close.includes("markNotes();"));
});
