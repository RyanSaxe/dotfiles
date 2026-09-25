#!/usr/bin/env node
import { execFile, execFileSync, spawn } from "node:child_process";
import crypto from "node:crypto";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import fs from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { choiceText } from "../assets/choices.mjs";

const here = fileURLToPath(import.meta.url);
const round = path.resolve(path.dirname(here), "../references/round.md");
export const version = crypto
  .createHash("sha256")
  .update(readFileSync(here))
  .digest("hex")
  .slice(0, 12);
const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$/;
const revisionPattern = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$/;
const configScript =
  /(<script\b(?=[^>]*\bid=["']session-config["'])[^>]*>)[\s\S]*?(<\/script>)/i;
const json = (value) => JSON.stringify(value, null, 2);
const exists = async (file) =>
  fs.access(file).then(
    () => true,
    () => false,
  );
const read = async (file) => JSON.parse(await fs.readFile(file, "utf8"));
const timestamp = () => new Date().toISOString();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
function requireValue(condition, message, code = 400) {
  if (!condition) throw Object.assign(new Error(message), { statusCode: code });
}
async function atomic(file, value) {
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(temporary, json(value), { mode: 0o600 });
  await fs.rename(temporary, file);
}
function embedConfig(html, config) {
  const script = json(config).replaceAll("<", "\\u003c");
  return html.replace(
    configScript,
    () =>
      `<script type="application/json" id="session-config">${script}</script>`,
  );
}

export function settings(env = process.env) {
  const home = env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
  const root = path.join(home, "interactive-plan");
  const port =
    env.INTERACTIVE_PLAN_PORT === undefined
      ? 4747
      : Number(env.INTERACTIVE_PLAN_PORT);
  requireValue(
    Number.isInteger(port) && port >= 0 && port <= 65535,
    "INTERACTIVE_PLAN_PORT must be a port number",
  );
  const seconds = (name, fallback) => {
    if (env[name] === undefined) return fallback;
    const value = Number(env[name]);
    requireValue(
      Number.isFinite(value) && value >= 0,
      `${name} must be a number of seconds`,
    );
    return value;
  };
  return {
    root,
    sessions: path.join(root, "sessions"),
    hubDir: path.join(root, "hub"),
    hubFile: path.join(root, "hub", "hub.json"),
    hubLog: path.join(root, "hub", "hub.log"),
    port,
    host: env.INTERACTIVE_PLAN_HOST || null,
    idleMs: seconds("INTERACTIVE_PLAN_IDLE_SECONDS", 900) * 1000,
  };
}

export function artifactData(html) {
  const match = html.match(
    /<script\b(?=[^>]*\bid=["']plan-data["'])(?=[^>]*\btype=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/i,
  );
  requireValue(
    match,
    'HTML requires an application/json script with id="plan-data"',
  );
  const data = JSON.parse(match[1]);
  requireValue(idPattern.test(data.artifactId || ""), "Invalid artifactId");
  requireValue(revisionPattern.test(data.revision || ""), "Invalid revision");
  requireValue(
    ["exploration", "plan"].includes(data.kind),
    "kind must be exploration or plan",
  );
  requireValue(
    typeof data.title === "string" && data.title.trim(),
    "title is required",
  );
  requireValue(
    Array.isArray(data.pages) &&
      (data.pages.length > 0 || data.pageMode === "partial"),
    "At least one page is required",
  );
  const ids = new Set();
  if (data.agreements !== undefined) {
    requireValue(Array.isArray(data.agreements), "agreements must be an array");
    const agreementIds = new Set();
    for (const entry of data.agreements) {
      requireValue(
        entry &&
          typeof entry.id === "string" &&
          idPattern.test(entry.id) &&
          !agreementIds.has(entry.id),
        "Agreement IDs must be valid and unique",
      );
      agreementIds.add(entry.id);
      requireValue(
        ["title", "html"].every(
          (key) => typeof entry[key] === "string" && entry[key].trim(),
        ),
        "Agreements require title and html",
      );
      requireValue(
        (typeof entry.source === "string" && entry.source.trim()) ||
          (Array.isArray(entry.sourceRefs) && entry.sourceRefs.length > 0),
        "Agreements require source text or sourceRefs",
      );
      if (entry.sourceRefs !== undefined) {
        requireValue(
          Array.isArray(entry.sourceRefs),
          "sourceRefs must be an array",
        );
        for (const ref of entry.sourceRefs) {
          requireValue(
            ref &&
              ["note", "choice", "answer", "conversation"].includes(ref.kind),
            "Invalid source reference kind",
          );
          if (ref.kind === "conversation")
            requireValue(
              typeof ref.text === "string" && ref.text.trim(),
              "Conversation source requires text",
            );
          else {
            requireValue(
              idPattern.test(ref.submissionId || ""),
              "Invalid source submission ID",
            );
            const key = sourceItemKey(ref.kind);
            requireValue(
              typeof ref[key] === "string" && ref[key].length > 0,
              "Source reference requires an item ID",
            );
          }
        }
      }
      requireValue(
        entry.state === undefined ||
          ["agreed", "reopened", "retired"].includes(entry.state),
        "Invalid agreement state",
      );
      requireValue(
        entry.change === undefined || ["new", "updated"].includes(entry.change),
        "Invalid agreement change",
      );
      if (entry.href !== undefined) {
        requireValue(
          typeof entry.href === "string" && entry.href.trim(),
          "Invalid agreement source URL",
        );
        const url = new URL(entry.href, "http://127.0.0.1/");
        requireValue(
          ["http:", "https:"].includes(url.protocol),
          "Unsafe agreement source URL",
        );
      }
    }
  }
  const prototypeIds = new Set();
  if (data.prototypes !== undefined) {
    requireValue(Array.isArray(data.prototypes), "prototypes must be an array");
    for (const prototype of data.prototypes) {
      requireValue(
        prototype &&
          idPattern.test(prototype.id || "") &&
          !prototypeIds.has(prototype.id),
        "Prototype IDs must be valid and unique",
      );
      prototypeIds.add(prototype.id);
      requireValue(
        typeof prototype.title === "string" &&
          prototype.title.trim() &&
          typeof prototype.html === "string" &&
          prototype.html.trim(),
        "Prototypes require title and HTML",
      );
      requireValue(
        Number.isFinite(prototype.height) && prototype.height > 0,
        "Prototype height must be positive",
      );
    }
  }
  for (const page of data.pages) {
    requireValue(
      idPattern.test(page.id || "") &&
        !["agreed", "feedback"].includes(page.id) &&
        !ids.has(page.id),
      "Page IDs must be unique; agreed and feedback are reserved",
    );
    requireValue(
      typeof page.title === "string" &&
        page.title.trim() &&
        typeof page.html === "string",
      "Pages require title and html",
    );
    ids.add(page.id);
  }
  if (data.task !== undefined) validTask(data.task);
  for (const content of [...data.pages, ...(data.agreements || [])]) {
    for (const match of content.html.matchAll(
      /<[a-z][^>]*?\sdata-prototype\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi,
    ))
      requireValue(
        prototypeIds.has(match[1] ?? match[2] ?? match[3]),
        "Unknown prototype reference",
      );
  }
  requireValue(
    data.kind !== "plan" ||
      data.pageMode === "partial" ||
      data.pages[0].id === "overview",
    "A final plan starts with an overview page",
  );
  return data;
}
// The task opens Agreed: what the plan is building towards, in a title and a
// few sentences.
function validTask(task) {
  requireValue(
    task && typeof task === "object" && !Array.isArray(task),
    'page "agreed": Agreed has no task. State what the plan is building towards.',
  );
  requireValue(
    typeof task.title === "string" && task.title.trim(),
    'page "agreed": the task has no title',
  );
  requireValue(
    typeof task.html === "string" && task.html.trim(),
    'page "agreed": the task has no text',
  );
  requireValue(
    task.change === undefined || ["new", "updated"].includes(task.change),
    'page "agreed": the task\'s change is new or updated',
  );
}
export function pageData(html) {
  const match = html.match(
    /<script\b(?=[^>]*\bid=["']page-data["'])(?=[^>]*\btype=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/i,
  );
  let record;
  try {
    record = JSON.parse(match ? match[1] : html);
  } catch {
    requireValue(false, "Invalid page record");
  }
  const page = record?.page;
  requireValue(page && typeof page === "object", "Page record requires page");
  requireValue(
    idPattern.test(page.id || "") && page.id !== "feedback",
    "Invalid page ID",
  );
  requireValue(
    typeof page.title === "string" && page.title.trim(),
    "Page title is required",
  );
  requireValue(
    page.id === "agreed"
      ? Array.isArray(page.agreements)
      : typeof page.html === "string" && page.html.trim(),
    "Agreed requires agreements; other pages require HTML",
  );
  if (page.id === "agreed") validTask(page.task);
  for (const key of ["cssText", "jsText"])
    requireValue(
      page[key] === undefined || typeof page[key] === "string",
      `${key} must be text`,
    );
  if (page.jsText)
    requireValue(
      /export\s+(?:async\s+)?function\s+setup\s*\(/.test(page.jsText),
      "Page JavaScript must export setup(root, planUI)",
    );
  if (
    /<\/style/i.test(page.cssText || "") ||
    /<\/script/i.test(page.jsText || "")
  )
    requireValue(false, "Page CSS/JS cannot contain closing style/script tags");
  artifactData(
    `<script type="application/json" id="plan-data">${JSON.stringify({
      artifactId: record.artifactId,
      revision: record.revision,
      kind: record.kind,
      title: record.title,
      pageMode: "partial",
      pages:
        page.id === "agreed"
          ? []
          : [{ id: page.id, title: page.title, html: page.html }],
      agreements: page.id === "agreed" ? page.agreements : [],
      task: page.id === "agreed" ? page.task : undefined,
      prototypes: page.prototypes || [],
    }).replaceAll("<", "\\u003c")}</script>`,
  );
  return record;
}
function pageList(items, kind) {
  requireValue(
    Array.isArray(items) && items.length > 0,
    "List at least one page",
  );
  const ids = new Set();
  for (const item of items) {
    requireValue(
      item &&
        idPattern.test(item.id || "") &&
        !["agreed", "feedback"].includes(item.id) &&
        !ids.has(item.id) &&
        typeof item.title === "string" &&
        item.title.trim(),
      "Page IDs and titles must be valid and unique",
    );
    ids.add(item.id);
  }
  requireValue(
    kind !== "plan" || items[0].id === "overview",
    "A final plan lists overview first",
  );
  return items.map(({ id, title }) => ({
    id,
    title,
    state: "queued",
    version: null,
  }));
}
function sourceItemKey(kind) {
  return { note: "noteId", choice: "choiceId", answer: "answerId" }[kind];
}
function sourceItem(payload, ref) {
  if (ref.kind === "note")
    return payload.groups?.notes?.find((note) => note.id === ref.noteId);
  if (ref.kind === "choice") return payload.groups?.choices?.[ref.choiceId];
  return payload.groups?.answers?.[ref.answerId];
}

function serializer() {
  let queue = Promise.resolve();
  return (fn) => {
    const result = queue.then(fn);
    queue = result.catch(() => {});
    return result;
  };
}

async function loadSession(directory, config, origin) {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  for (const child of ["artifacts", "feedback", "uploads", "scenes"])
    await fs.mkdir(path.join(directory, child), {
      recursive: true,
      mode: 0o700,
    });
  const stateFile = path.join(directory, "status.json");
  let state = (await exists(stateFile))
    ? await read(stateFile)
    : {
        sessionId: crypto.randomUUID(),
        stage: "ready",
        current: null,
        acknowledged: [],
        accepted: null,
        updatedAt: timestamp(),
      };
  requireValue(
    idPattern.test(state.sessionId) && Array.isArray(state.acknowledged),
    "Invalid session state",
  );
  const connectionFile = path.join(directory, "connection.json");
  let token = null;
  if (await exists(connectionFile)) {
    const connection = await read(connectionFile);
    if (
      connection.sessionId === state.sessionId &&
      /^[0-9a-f]{64}$/.test(connection.token || "")
    )
      token = connection.token;
  }
  token ||= crypto.randomBytes(32).toString("hex");
  const base = `/s/${state.sessionId}`;
  const exclusive = serializer();
  // The wake target holds a token or a socket path, so it lives in its own
  // agent-private file and never in a browser response.
  const wakeFile = path.join(directory, "wake.json");
  let wake = (await exists(wakeFile)) ? await read(wakeFile) : null;
  const transition = async (patch) => {
    const next = { ...state, ...patch, updatedAt: timestamp() };
    await atomic(stateFile, next);
    state = next;
    return state;
  };
  async function events() {
    const files = (await fs.readdir(path.join(directory, "feedback"))).filter(
      (name) => name.endsWith(".json"),
    );
    return Promise.all(
      files.map((name) => read(path.join(directory, "feedback", name))),
    );
  }
  let sequence = (await events()).reduce(
    (last, event) => Math.max(last, event.sequence),
    0,
  );
  async function pending() {
    return (await events())
      .filter((event) => !state.acknowledged.includes(event.id))
      .sort((a, b) => a.sequence - b.sequence);
  }
  if ((await pending()).length) await transition({ stage: "submitted" });
  else await atomic(stateFile, state);
  const sameArtifact = (event) =>
    state.current &&
    event.artifactId === state.current.artifactId &&
    event.revision === state.current.revision;
  const needsYou = () =>
    Boolean(state.current) &&
    !state.pageRound &&
    ["ready", "updated"].includes(state.stage);
  const active = () => state.stage !== "complete" && !state.paused;
  function withDrawingPaths(event) {
    const answers = event.payload.groups?.answers;
    if (
      !answers ||
      !Object.values(answers).some((item) => item.kind === "drawing")
    )
      return event;
    const mapped = Object.fromEntries(
      Object.entries(answers).map(([key, answer]) => [
        key,
        answer.kind === "drawing"
          ? {
              ...answer,
              scenePath: path.join(
                directory,
                "scenes",
                `${answer.sceneId}.excalidraw`,
              ),
              previewPath: path.join(
                directory,
                "uploads",
                `${answer.previewId}.png`,
              ),
            }
          : answer,
      ]),
    );
    return {
      ...event,
      payload: {
        ...event.payload,
        groups: { ...event.payload.groups, answers: mapped },
      },
    };
  }
  // Runs after the submission is saved, outside the browser's request, so a
  // slow or failing harness never delays the reviewer's Sent state.
  async function wakeAgent(revision) {
    const line = `interactive-plan: feedback arrived on session ${directory} (revision ${revision}). Run: node ${here} read --session-dir ${directory}, then follow ${round}`;
    let last;
    try {
      await (config.wake || wakeRunner)(wake, line);
      last = { at: timestamp(), ok: true };
    } catch (error) {
      last = { at: timestamp(), ok: false, reason: error.message };
    }
    await transition({ wake: { harness: wake.harness, last } });
  }
  /* Closing a session from the browser. complete() refuses without an
     acceptance, so ending an abandoned session needs its own door. */
  async function dismiss() {
    await transition({ stage: "complete", dismissedAt: timestamp() });
    return { status: view() };
  }
  /* The hub names every file, so a caller never chooses a path and a name
     can never escape the uploads directory. */
  async function upload(bytes) {
    const kind = imageKind(bytes);
    requireValue(kind, "Only PNG, JPEG, WebP and GIF images are accepted", 415);
    const id = crypto.randomBytes(8).toString("hex");
    const file = path.join(directory, "uploads", `${id}.${kind.ext}`);
    await fs.writeFile(file, bytes, { mode: 0o600 });
    return { id, path: file, type: kind.type, bytes: bytes.length };
  }
  async function readUpload(id) {
    requireValue(/^[0-9a-f]{16}$/.test(id || ""), "Bad image ID", 404);
    const held = await fs.readdir(path.join(directory, "uploads"));
    const name = held.find((entry) => entry.startsWith(`${id}.`));
    requireValue(name, "No such image", 404);
    const bytes = await fs.readFile(path.join(directory, "uploads", name));
    const kind = imageKind(bytes);
    requireValue(kind, "No such image", 404);
    return { bytes, type: kind.type };
  }
  async function uploadScene(bytes) {
    let scene;
    try {
      scene = JSON.parse(bytes.toString("utf8"));
    } catch {
      requireValue(false, "Drawing scene must be JSON");
    }
    requireValue(
      scene?.type === "excalidraw" &&
        Array.isArray(scene.elements) &&
        scene.elements.length > 0 &&
        scene.appState &&
        typeof scene.appState === "object" &&
        !Array.isArray(scene.appState) &&
        scene.files &&
        typeof scene.files === "object" &&
        !Array.isArray(scene.files),
      "Drawing scene must contain Excalidraw elements, appState and files",
    );
    const id = crypto.randomBytes(8).toString("hex");
    const file = path.join(directory, "scenes", `${id}.excalidraw`);
    await fs.writeFile(file, bytes, { mode: 0o600 });
    return {
      id,
      path: file,
      type: "application/vnd.excalidraw+json",
      bytes: bytes.length,
    };
  }
  async function readScene(id) {
    requireValue(/^[0-9a-f]{16}$/.test(id || ""), "Bad drawing scene ID", 404);
    const file = path.join(directory, "scenes", `${id}.excalidraw`);
    requireValue(await exists(file), "No such drawing scene", 404);
    return { bytes: await fs.readFile(file), path: file };
  }
  /* A note the reviewer removed takes its images with it. */
  async function removeUpload(id) {
    requireValue(/^[0-9a-f]{16}$/.test(id || ""), "Bad image ID");
    const held = await fs.readdir(path.join(directory, "uploads"));
    const name = held.find((entry) => entry.startsWith(`${id}.`));
    if (name) await fs.rm(path.join(directory, "uploads", name));
    return { id, removed: Boolean(name) };
  }
  async function submit(data) {
    requireValue(data.sessionId === state.sessionId, "Wrong session", 409);
    requireValue(
      idPattern.test(data.id || "") &&
        typeof data.text === "string" &&
        data.text.trim(),
      "Submission requires ID and text",
    );
    requireValue(
      ["feedback-only", "accept-plan"].includes(data.intent),
      "Invalid submission intent",
    );
    requireValue(
      data.groups &&
        typeof data.groups === "object" &&
        !Array.isArray(data.groups),
      "groups must be an object",
    );
    if (
      data.intent === "feedback-only" &&
      data.groups.alignUnflagged !== undefined
    )
      requireValue(
        typeof data.groups.alignUnflagged === "boolean",
        "alignUnflagged must be a boolean",
      );
    if (data.groups.answers !== undefined) {
      requireValue(
        data.groups.answers &&
          typeof data.groups.answers === "object" &&
          !Array.isArray(data.groups.answers),
        "answers must be an object",
      );
      for (const answer of Object.values(data.groups.answers)) {
        if (answer?.kind === "drawing") {
          requireValue(
            ["label", "topic", "revision", "sceneId", "previewId"].every(
              (key) => typeof answer[key] === "string" && answer[key],
            ),
            "Drawing answers require label, topic, revision and both file IDs",
          );
          await readScene(answer.sceneId);
          const preview = await readUpload(answer.previewId);
          requireValue(
            preview.type === "image/png",
            "Drawing preview must be PNG",
          );
        } else
          requireValue(
            answer &&
              answer.kind === undefined &&
              ["label", "text", "topic"].every(
                (key) => typeof answer[key] === "string",
              ) &&
              answer.text.trim(),
            "Answers require label, text, and topic",
          );
      }
    }
    /* Images hang off the note they illustrate, and a note may only name an
       image this session holds, so a submission cannot point the agent at a
       path the hub never wrote. */
    if (Array.isArray(data.groups.notes)) {
      const held = new Set(
        (await fs.readdir(path.join(directory, "uploads"))).map((name) =>
          name.slice(0, name.indexOf(".")),
        ),
      );
      for (const note of data.groups.notes) {
        if (note?.attachments === undefined) continue;
        requireValue(
          Array.isArray(note.attachments),
          "A note's attachments must be an array",
        );
        for (const item of note.attachments) {
          requireValue(
            item &&
              typeof item.id === "string" &&
              typeof item.path === "string" &&
              typeof item.type === "string" &&
              Number.isInteger(item.bytes),
            "An attachment needs id, path, type and bytes",
          );
          requireValue(
            held.has(item.id),
            `Image ${item.id} is not in this session`,
          );
        }
      }
    }
    if (data.intent === "accept-plan") {
      requireValue(
        ["save", "implement"].includes(data.mode),
        "Choose save or implement explicitly",
      );
      if (data.guidance !== undefined) {
        requireValue(
          data.mode === "implement" && typeof data.guidance === "string",
          "Only implementation acceptance can include guidance",
        );
        data.guidance = data.guidance.trim();
        requireValue(
          data.guidance.length <= 4000,
          "Implementation guidance exceeds 4,000 characters",
        );
        if (!data.guidance) delete data.guidance;
      }
    }
    const file = path.join(directory, "feedback", data.id + ".json");
    if (await exists(file)) {
      const original = await read(file);
      requireValue(
        isDeepStrictEqual(original.payload, data),
        "Submission ID already has different content",
        409,
      );
      return { id: data.id, saved: true, status: view() };
    }
    requireValue(
      sameArtifact(data),
      "Review the current artifact before submitting; export older drafts if needed",
      409,
    );
    if (data.intent === "accept-plan") {
      requireValue(
        state.current.kind === "plan" &&
          ["ready", "updated"].includes(state.stage) &&
          !(await pending()).length,
        "Resolve feedback before accepting the current final plan",
        409,
      );
    }
    requireValue(
      !state.pageRound,
      "Finish every listed page before submitting feedback",
      409,
    );
    await atomic(file, {
      id: data.id,
      sequence: ++sequence,
      receivedAt: timestamp(),
      payload: data,
    });
    await transition({
      stage:
        data.intent === "feedback-only" && state.stage === "working"
          ? "working"
          : "submitted",
      latestSubmissionId: data.id,
      latestSubmissionRevision:
        data.intent === "feedback-only" ? data.revision : null,
      wake: state.wake ? { ...state.wake, last: null } : null,
      accepted: null,
    });
    if (wake && !state.paused)
      setTimeout(() => exclusive(() => wakeAgent(data.revision)), 0);
    return { id: data.id, saved: true, status: view() };
  }
  async function resolvePageAgreements(entries) {
    const submissions = await events();
    for (const entry of entries) {
      delete entry.sourceRecords;
      if (!entry.sourceRefs) continue;
      entry.sourceRecords = [];
      for (const ref of entry.sourceRefs) {
        if (ref.kind === "conversation") {
          entry.sourceRecords.push({ kind: ref.kind, text: ref.text });
          continue;
        }
        const event = submissions.find((item) => item.id === ref.submissionId);
        requireValue(event, "Source submission not found");
        const item = sourceItem(event.payload, ref);
        requireValue(
          item && typeof item.topic === "string",
          "Source item not found",
        );
        const text = ref.kind === "choice" ? choiceText(item) : item.text;
        const label = ref.kind === "note" ? item.anchor : item.label;
        requireValue(
          typeof text === "string" && typeof label === "string",
          "Source item has invalid content",
        );
        const target =
          typeof item.target === "string" && idPattern.test(item.target)
            ? item.target
            : null;
        const payload = event.payload;
        requireValue(
          idPattern.test(payload.artifactId || "") &&
            revisionPattern.test(payload.revision || ""),
          "Invalid source artifact",
        );
        const href = `./${payload.artifactId}.${payload.revision}.html${target ? "?target=" + encodeURIComponent(target) : ""}#${encodeURIComponent(item.topic)}`;
        entry.sourceRecords.push({
          kind: ref.kind,
          submissionId: ref.submissionId,
          text,
          label,
          topic: item.topic,
          artifactId: payload.artifactId,
          revision: payload.revision,
          href,
          ...(target ? { target } : {}),
          ...(ref.kind === "choice" ? { choice: item } : {}),
          ...(typeof item.quote === "string" ? { quote: item.quote } : {}),
        });
      }
    }
  }
  const storedPagePath = (round, file) =>
    path.join(directory, "pages", round.revision, path.basename(file));
  async function renderPageRound(round) {
    const { assemble, pageScope, pageScripts } = await import("./build.mjs");
    const bundle = await read(storedPagePath(round, round.bundlePath));
    const agreed = await read(storedPagePath(round, round.agreed));
    const records = await Promise.all(
      (round.pages || [])
        .filter((slot) => slot.recordPath)
        .map((slot) => read(storedPagePath(round, slot.recordPath))),
    );
    const ready = new Map(
      records.map((record) => [record.page.id, record.page]),
    );
    const complete =
      Boolean(round.pages?.length) &&
      round.pages.every((slot) => slot.recordPath);
    const pages = (round.pages || []).map((slot) => ({
      id: slot.id,
      title: slot.title,
      html: ready.get(slot.id)?.html || "",
      pending: !slot.recordPath,
      working: slot.state === "active",
    }));
    const all = [agreed.page, ...records.map((record) => record.page)];
    const css = all
      .filter((page) => page.cssText)
      .map(
        (page) =>
          `@scope (${pageScope(page.id, round.revision)}) { ${page.cssText} }`,
      )
      .join("\n");
    const data = {
      artifactId: round.artifactId,
      revision: round.revision,
      kind: round.kind,
      title: round.title,
      ...(complete ? {} : { pageMode: "partial" }),
      pages,
      agreements: agreed.page.agreements,
      task: agreed.page.task,
      prototypes: all.flatMap((page) => page.prototypes || []),
    };
    const html = await assemble(data, {
      css,
      js: pageScripts(all, round.revision),
      allowUnknownPages: !complete,
      bundle,
    });
    return { html, complete };
  }
  async function commitPageRound(round, source = null) {
    const complete = round.pages.every((slot) => slot.recordPath);
    let current = state.current;
    if (!current || current.revision !== round.revision || complete) {
      let html;
      try {
        ({ html } = await renderPageRound(round));
      } catch (error) {
        error.statusCode ||= 400;
        throw error;
      }
      const stored = embedConfig(html, { sessionId: state.sessionId, base });
      const name = complete
        ? `${round.artifactId}.${round.revision}.html`
        : `${round.artifactId}.${round.revision}.live.html`;
      const file = path.join(directory, "artifacts", name);
      const temporary = `${file}.${crypto.randomUUID()}.tmp`;
      await fs.writeFile(temporary, stored, { mode: 0o600, flag: "wx" });
      await fs.rename(temporary, file);
      current = {
        artifactId: round.artifactId,
        revision: round.revision,
        kind: round.kind,
        title: round.title,
        path: file,
        url: base + "/",
        sha256: crypto.createHash("sha256").update(stored).digest("hex"),
        publishedAt: timestamp(),
        source,
      };
    }
    const revisions = complete
      ? [
          ...(state.revisions || []),
          {
            artifactId: round.artifactId,
            revision: round.revision,
            kind: round.kind,
            title: round.title,
            publishedAt: current.publishedAt,
            url: `${base}/r/${encodeURIComponent(round.revision)}`,
          },
        ]
      : state.revisions || [];
    await transition({
      pageRound: complete ? null : round,
      pageSets: { ...(state.pageSets || {}), [round.revision]: round },
      pageSetGeneration: round.generation,
      stage: complete ? "updated" : "working",
      current,
      title: round.title,
      kind: round.kind,
      revisions,
      accepted: null,
    });
    return { status: view(), url: origin + current.url, complete };
  }
  async function publishPage(html, source, pages) {
    requireValue(
      !(await pending()).length,
      "Read pending feedback before publishing",
      409,
    );
    requireValue(
      ["ready", "working"].includes(state.stage),
      "Read feedback before publishing a page",
      409,
    );
    requireValue(
      source === undefined ||
        (typeof source === "string" &&
          path.resolve(source).startsWith(directory + path.sep)),
      "Source must be a directory inside the session directory",
    );
    requireValue(
      configScript.test(html),
      "HTML requires a session-config JSON script",
    );
    requireValue(
      /\bid=["']page-data["']/.test(html),
      "HTML requires a page-data JSON script",
    );
    const record = pageData(html);
    const { page } = record;
    requireValue(
      page.id === "agreed" || pages === undefined,
      "--pages is only valid when publishing Agreed",
    );
    let round;
    if (page.id === "agreed") {
      const slots = pageList(pages, record.kind);
      requireValue(
        !state.pageRound,
        "Agreed is already published for this revision",
        409,
      );
      requireValue(
        !(state.revisions || []).some(
          (item) => item.revision === record.revision,
        ),
        `Revision ${record.revision} is already used`,
        409,
      );
      await resolvePageAgreements(page.agreements);
      const previous = state.pageSets?.[state.current?.revision];
      if (previous?.agreed) {
        const earlier = (await read(storedPagePath(previous, previous.agreed)))
          .page.agreements;
        const byId = new Map(earlier.map((entry) => [entry.id, entry]));
        const nextOrder =
          Math.max(0, ...earlier.map((entry) => entry.lastChangedOrder || 0)) +
          1;
        page.agreements.forEach((entry, index) => {
          const old = byId.get(entry.id);
          const same =
            old &&
            ["title", "html", "state"].every(
              (key) => (old[key] || null) === (entry[key] || null),
            );
          entry.lastChangedOrder = same ? old.lastChangedOrder || 0 : nextOrder;
          entry.authoredOrder = index;
        });
      } else
        page.agreements.forEach((entry, index) => {
          entry.lastChangedOrder = 1;
          entry.authoredOrder = index;
        });
      page.agreements.sort(
        (a, b) =>
          b.lastChangedOrder - a.lastChangedOrder ||
          a.authoredOrder - b.authoredOrder,
      );
      round = {
        artifactId: record.artifactId,
        revision: record.revision,
        kind: record.kind,
        title: record.title,
        agreed: null,
        pages: slots,
        bundlePath: null,
        generation: 1,
      };
    } else {
      requireValue(state.pageRound, "Publish Agreed before other pages", 409);
      round = structuredClone(state.pageRound);
      requireValue(
        ["artifactId", "revision", "kind", "title"].every(
          (key) => record[key] === round[key],
        ),
        "Page does not match this revision",
        409,
      );
      const slot = round.pages?.find((item) => item.id === page.id);
      requireValue(
        slot && slot.title === page.title,
        "Page is not in this revision's list",
        409,
      );
      requireValue(!slot.recordPath, "Page is already published", 409);
      const used = new Set([
        ...((
          await read(storedPagePath(round, round.agreed))
        ).page.prototypes?.map((item) => item.id) || []),
      ]);
      for (const entry of round.pages.filter((item) => item.recordPath))
        for (const item of (await read(storedPagePath(round, entry.recordPath)))
          .page.prototypes || [])
          used.add(item.id);
      requireValue(
        !(page.prototypes || []).some((item) => used.has(item.id)),
        "Prototype ID is already used in this revision",
        409,
      );
    }
    const recordDir = path.join(directory, "pages", record.revision);
    await fs.mkdir(recordDir, { recursive: true, mode: 0o700 });
    const recordPath = path.join(
      recordDir,
      `${page.id}.${crypto.randomUUID()}.json`,
    );
    const recordBytes = json(record);
    await fs.writeFile(recordPath, recordBytes, { mode: 0o600, flag: "wx" });
    const version = crypto
      .createHash("sha256")
      .update(recordBytes)
      .digest("hex");
    if (page.id === "agreed") {
      round.agreed = recordPath;
      round.agreedVersion = version;
    } else {
      const slot = round.pages.find((item) => item.id === page.id);
      slot.recordPath = recordPath;
      slot.state = "ready";
      slot.version = version;
      round.generation++;
    }
    if (page.id === "agreed") {
      const { frameBundle } = await import("./build.mjs");
      round.bundlePath = path.join(
        recordDir,
        `frame.${crypto.randomUUID()}.json`,
      );
      await fs.writeFile(round.bundlePath, json(await frameBundle()), {
        mode: 0o600,
        flag: "wx",
      });
    }
    const result = await commitPageRound(round, source);
    return {
      ...result,
      page: {
        id: page.id,
        revision: record.revision,
        version,
        recordPath,
      },
    };
  }
  async function pageProgress(data) {
    requireValue(
      state.pageRound && state.stage === "working",
      "Publish Agreed first",
      409,
    );
    const round = structuredClone(state.pageRound);
    requireValue(
      data.pages === undefined &&
        data.done === undefined &&
        Array.isArray(data.start) &&
        data.start.length > 0,
      "Page progress only takes --start; publishing marks a page done",
    );
    for (const id of data.start) {
      const slot = round.pages.find((item) => item.id === id);
      requireValue(
        slot && !slot.recordPath,
        `Unknown or ready page ${id}`,
        409,
      );
      slot.state = "active";
    }
    round.generation++;
    return commitPageRound(round);
  }
  async function act(data) {
    requireValue(data.sessionId === state.sessionId, "Wrong session", 409);
    if (data.action === "read") {
      // With an id, read returns that submission again and changes nothing,
      // for a turn that resumes after an interruption.
      if (data.id !== undefined) {
        requireValue(idPattern.test(data.id || ""), "Submission ID required");
        const event = await read(
          path.join(directory, "feedback", data.id + ".json"),
        );
        return { status: view(), event: withDrawingPaths(event) };
      }
      const [event] = await pending();
      if (!event) return { status: view(), event: null };
      const patch = {
        stage: "working",
        acknowledged: [...state.acknowledged, event.id],
        acknowledgedAt: timestamp(),
        lastAcknowledgedId: event.id,
      };
      if (event.payload.intent === "accept-plan") {
        requireValue(
          sameArtifact(event.payload),
          "Acceptance no longer matches the current plan",
          409,
        );
        patch.accepted = {
          eventId: event.id,
          ...state.current,
          mode: event.payload.mode,
          ...(event.payload.guidance
            ? { guidance: event.payload.guidance }
            : {}),
          acceptedAt: event.receivedAt,
        };
        await atomic(path.join(directory, "acceptance.json"), patch.accepted);
      }
      await transition(patch);
      return { status: view(), event: withDrawingPaths(event) };
    }
    if (data.action === "progress") {
      return pageProgress(data);
    }
    if (data.action === "pause") {
      requireValue(
        typeof data.reason === "string" && data.reason.trim(),
        "pause requires a reason",
      );
      await transition({
        paused: { at: timestamp(), reason: data.reason.trim() },
      });
      return { status: view() };
    }
    if (data.action === "publish")
      return publishPage(data.html, data.source, data.pages);
    if (data.action === "complete") {
      requireValue(
        state.accepted &&
          state.accepted.sha256 === state.current?.sha256 &&
          !(await pending()).length,
        "Acknowledge acceptance of the current plan before completing",
        409,
      );
      await transition({ stage: "complete" });
      return {
        status: view(),
        planPath: state.accepted.path,
        nextAction: state.accepted.mode === "implement" ? "implement" : "save",
        ...(state.accepted.guidance
          ? { guidance: state.accepted.guidance }
          : {}),
      };
    }
    requireValue(false, "Unknown agent action");
  }
  function view() {
    const { pageSets, ...visible } = state;
    return {
      ...visible,
      ...(state.pageRound
        ? {
            pageRound: {
              revision: state.pageRound.revision,
              pages: state.pageRound.pages.map(({ id, title, state }) => ({
                id,
                title,
                state,
              })),
            },
          }
        : {}),
      revisions: state.revisions || [],
      wake: state.wake || null,
      paused: state.paused || null,
      needsYou: needsYou(),
    };
  }
  async function latestFeedback(requestedRevision) {
    requireValue(
      requestedRevision === null || revisionPattern.test(requestedRevision),
      "Invalid revision",
    );
    const event = requestedRevision
      ? (await events())
          .filter(
            (item) =>
              item.payload.intent === "feedback-only" &&
              item.payload.revision === requestedRevision,
          )
          .sort((a, b) => b.sequence - a.sequence)[0]
      : state.latestSubmissionId && idPattern.test(state.latestSubmissionId)
        ? await read(
            path.join(
              directory,
              "feedback",
              `${state.latestSubmissionId}.json`,
            ),
          )
        : null;
    if (!event) return null;
    if (event.payload.intent !== "feedback-only") return null;
    const { groups, revision } = event.payload;
    return {
      id: event.id,
      revision,
      receivedAt: event.receivedAt,
      groups: {
        alignUnflagged: groups.alignUnflagged,
        notes: (groups.notes || []).map(
          ({ topic, anchor, quote, text, attachments }) => ({
            topic,
            anchor,
            quote,
            text,
            attachments: (attachments || []).map(({ id }) => ({ id })),
          }),
        ),
        choices: groups.choices || {},
        answers: groups.answers || {},
      },
    };
  }
  function listing() {
    if (!state.current) return null;
    return {
      id: state.sessionId,
      title: state.current.title,
      kind: state.current.kind,
      revision: state.current.revision,
      stage: state.stage,
      needsYou: needsYou(),
      ...(state.pageRound
        ? {
            pageRound: {
              ready:
                1 +
                (state.pageRound.pages || []).filter((item) => item.recordPath)
                  .length,
            },
          }
        : {}),
      paused: Boolean(state.paused),
      publishedAt: state.current.publishedAt,
      updatedAt: state.updatedAt,
      url: base + "/",
    };
  }
  async function setWake(target) {
    await atomic(wakeFile, target);
    wake = target;
    await transition({
      wake: { harness: target.harness, last: state.wake?.last || null },
      paused: null,
    });
  }
  function revisionEntry(revision) {
    const entry = (state.revisions || []).find(
      (item) => item.revision === revision,
    );
    if (entry)
      return {
        ...entry,
        path: path.join(
          directory,
          "artifacts",
          `${entry.artifactId}.${entry.revision}.html`,
        ),
      };
    if (state.current?.revision === revision) return state.current;
    return null;
  }
  function pageSet(revision) {
    requireValue(revisionPattern.test(revision || ""), "Invalid revision");
    const round = state.pageSets?.[revision];
    requireValue(round, "Unknown revision", 404);
    return {
      revision,
      generation: round.generation,
      complete: round.pages.every((slot) => slot.recordPath),
      pages: [
        {
          id: "agreed",
          title: "Agreed so far",
          state: "ready",
          version: round.agreedVersion,
        },
        ...round.pages.map(({ id, title, state, version }) => ({
          id,
          title,
          state,
          version,
        })),
      ],
    };
  }
  async function pageRecord(revision, id, version) {
    const manifest = pageSet(revision);
    requireValue(
      idPattern.test(id || "") && /^[0-9a-f]{64}$/.test(version || ""),
      "Invalid page or version",
    );
    const slot = manifest.pages.find((item) => item.id === id);
    requireValue(slot && slot.version === version, "Unknown page version", 404);
    const round = state.pageSets[revision];
    return read(
      storedPagePath(
        round,
        id === "agreed"
          ? round.agreed
          : round.pages.find((item) => item.id === id).recordPath,
      ),
    );
  }
  async function prototype(revision, id) {
    requireValue(idPattern.test(id || ""), "Invalid prototype ID");
    // A revision published before page sets existed keeps its prototypes
    // only in its assembled HTML.
    const legacy = !state.pageSets?.[revision] && revisionEntry(revision);
    if (legacy) {
      const data = artifactData(await fs.readFile(legacy.path, "utf8"));
      const item = data.prototypes?.find((entry) => entry.id === id);
      requireValue(item, "Unknown prototype", 404);
      return item;
    }
    const manifest = pageSet(revision);
    for (const slot of manifest.pages.filter((item) => item.version)) {
      const record = await pageRecord(revision, slot.id, slot.version);
      const item = record.page.prototypes?.find((entry) => entry.id === id);
      if (item) return item;
    }
    requireValue(false, "Unknown prototype", 404);
  }
  return {
    directory,
    token,
    base,
    get id() {
      return state.sessionId;
    },
    get state() {
      return state;
    },
    exclusive,
    pending,
    submit,
    upload,
    readUpload,
    uploadScene,
    readScene,
    removeUpload,
    dismiss,
    act,
    view,
    latestFeedback,
    listing,
    active,
    setWake,
    revisionEntry,
    pageSet,
    pageRecord,
    prototype,
  };
}

/* An image is identified by its leading bytes, not by a Content-Type a
   caller sets or an extension a name carries. Anything else is refused, so
   the hub never writes a file it could not name. */
const signatures = [
  {
    type: "image/png",
    ext: "png",
    magic: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  },
  { type: "image/jpeg", ext: "jpg", magic: [0xff, 0xd8, 0xff] },
  { type: "image/gif", ext: "gif", magic: [0x47, 0x49, 0x46, 0x38] },
];
function imageKind(bytes) {
  for (const entry of signatures)
    if (entry.magic.every((byte, at) => bytes[at] === byte)) return entry;
  // RIFF....WEBP: the four-byte size sits between the two markers.
  if (
    bytes.length >= 12 &&
    bytes.subarray(0, 4).toString("latin1") === "RIFF" &&
    bytes.subarray(8, 12).toString("latin1") === "WEBP"
  )
    return { type: "image/webp", ext: "webp" };
  return null;
}
/* One request is bounded, the session is not, which is how every other
   route here behaves: a publish takes 10MB and a session may hold any
   number of revisions. A reviewer attaching screenshots should never meet
   a ceiling mid-review. */
const uploadBytes = 10 * 1024 * 1024;
async function readBytes(req, limit) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    requireValue(size <= limit, "Image is over 10MB", 413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function readBody(req, limit) {
  requireValue(
    req.headers["content-type"] === "application/json",
    "JSON required",
    415,
  );
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    requireValue(Buffer.byteLength(raw) <= limit, "Request too large", 413);
  }
  return JSON.parse(raw);
}

const harnesses = { claude: "claude-code", codex: "codex", copilot: "copilot" };
// The nearest harness among the ancestors decides which session start belongs
// to, because a harness started inside another inherits the outer one's
// variables. Names are the executables: claude, codex, copilot.
function ancestors(pid = process.ppid) {
  const chain = [];
  for (let current = pid; current > 1;) {
    let line;
    try {
      line = execFileSync("ps", ["-o", "ppid=,comm=", "-p", String(current)], {
        encoding: "utf8",
      }).trim();
    } catch {
      break;
    }
    const match = /^(\d+)\s+(.*)$/.exec(line);
    if (!match) break;
    chain.push({ pid: current, command: path.basename(match[2].trim()) });
    current = Number(match[1]);
  }
  return chain;
}
function listeningPort(pid) {
  try {
    const out = execFileSync(
      "lsof",
      ["-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-nP", "-Fn"],
      { encoding: "utf8" },
    );
    const match = /^n127\.0\.0\.1:(\d+)$/m.exec(out);
    return match ? Number(match[1]) : null;
  } catch {
    return null;
  }
}
function copilotSdk(env) {
  const roots = [
    env.COPILOT_PKG_CACHE_HOME,
    path.join(os.homedir(), "Library", "Caches", "copilot"),
    env.XDG_CACHE_HOME && path.join(env.XDG_CACHE_HOME, "copilot"),
    path.join(os.homedir(), ".cache", "copilot"),
  ].filter(Boolean);
  const tried = roots.map((root) =>
    path.join(
      root,
      "pkg",
      `${process.platform}-${process.arch}`,
      env.COPILOT_CLI_BINARY_VERSION || "",
      "copilot-sdk",
      "index.js",
    ),
  );
  return {
    sdk: tried.find((candidate) => existsSync(candidate)) || null,
    tried,
  };
}
export function detectWake(
  env = process.env,
  tools = { ancestors, listeningPort, copilotSdk },
) {
  const chain = tools.ancestors();
  const nearest = chain.find((entry) => harnesses[entry.command]);
  const harness = nearest
    ? harnesses[nearest.command]
    : env.COPILOT_AGENT_SESSION_ID
      ? "copilot"
      : env.CODEX_THREAD_ID
        ? "codex"
        : env.CLAUDE_CODE_MESSAGING_SOCKET
          ? "claude-code"
          : null;
  requireValue(
    harness,
    "no wake path. This needs Claude Code, Codex, or Copilot, and none of their session variables is set.",
  );
  if (harness === "claude-code") {
    const socket = env.CLAUDE_CODE_MESSAGING_SOCKET;
    const token = env.CLAUDE_CODE_MESSAGING_TOKEN;
    requireValue(
      socket && token,
      "this Claude Code session exposes no inbox socket, so it cannot be woken.",
    );
    return { harness, socket, token };
  }
  if (harness === "codex") {
    requireValue(
      env.CODEX_THREAD_ID,
      "this Codex session exports no CODEX_THREAD_ID, so it cannot be woken.",
    );
    return { harness, thread: env.CODEX_THREAD_ID };
  }
  const sessionId = env.COPILOT_AGENT_SESSION_ID;
  requireValue(
    sessionId,
    "this Copilot session exports no COPILOT_AGENT_SESSION_ID, so it cannot be woken.",
  );
  const port = nearest ? tools.listeningPort(nearest.pid) : null;
  requireValue(
    port,
    `this Copilot session cannot be woken. Restart it with \`copilot --ui-server --resume ${sessionId}\` and run start again.`,
  );
  const { sdk, tried } = tools.copilotSdk(env);
  requireValue(
    sdk,
    `the Copilot SDK was not found at ${tried.join(", ")}, so this session cannot be woken.`,
  );
  return { harness, sessionId, port, sdk };
}
const wakeCopilotScript = path.join(path.dirname(here), "wake-copilot.mjs");
function run(file, args) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { timeout: 30_000 }, (error, stdout, stderr) => {
      if (error) reject(new Error((stderr || error.message).trim()));
      else resolve();
    });
  });
}
function wakeClaude({ socket, token }, line) {
  return new Promise((resolve, reject) => {
    const client = net.connect(socket);
    client.setTimeout(5000, () => client.destroy(new Error("timed out")));
    client.on("error", reject);
    client.on("close", resolve);
    client.end(
      JSON.stringify({ type: "auth", token }) +
        "\n" +
        JSON.stringify({
          type: "user",
          message: { role: "user", content: line },
        }) +
        "\n",
    );
  });
}
export function wakeRunner(target, line) {
  if (target.harness === "claude-code") return wakeClaude(target, line);
  if (target.harness === "codex")
    return run("codex", [
      "queue",
      "--thread",
      target.thread,
      "--message",
      line,
    ]);
  if (target.harness === "copilot")
    return run(process.execPath, [
      wakeCopilotScript,
      target.sdk,
      String(target.port),
      target.sessionId,
      line,
    ]);
  return Promise.reject(new Error(`unknown harness ${target.harness}`));
}

export async function startHub(config = settings()) {
  await fs.mkdir(config.hubDir, { recursive: true, mode: 0o700 });
  await fs.mkdir(config.sessions, { recursive: true, mode: 0o700 });
  const secret = crypto.randomBytes(32).toString("hex");
  const startedAt = timestamp();
  const registry = new Map();
  const byDirectory = new Map();
  const register = serializer();
  let origin = null,
    hostOrigin = null,
    allowedHosts = new Set();
  const log = (message) =>
    (config.log || console.log)(`${timestamp()} ${message}`);
  async function adopt(directory) {
    let session = byDirectory.get(directory);
    if (!session) {
      session = await loadSession(directory, config, origin);
      registry.set(session.id, session);
      byDirectory.set(directory, session);
    }
    return session;
  }
  const open = () =>
    [...registry.values()].filter(
      (session) => session.state.stage !== "complete",
    );
  const active = () => open().filter((session) => session.active());
  const listed = () =>
    open()
      .map((session) => session.listing())
      .filter(Boolean)
      .sort(
        (a, b) =>
          Number(b.needsYou) - Number(a.needsYou) ||
          (a.needsYou
            ? Date.parse(a.publishedAt) - Date.parse(b.publishedAt)
            : Date.parse(b.updatedAt) - Date.parse(a.updatedAt)),
      );
  const artifactPage = async (session, entry, flags = {}) => {
    requireValue(entry, "Unknown revision", 404);
    const html = await fs.readFile(entry.path, "utf8");
    return embedConfig(html, {
      sessionId: session.id,
      base: session.base,
      ...flags,
    });
  };
  async function handle(req, res) {
    const reply = (code, value, type = "application/json", headers = {}) => {
      res.writeHead(code, {
        "Content-Type": type,
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        ...headers,
      });
      res.end(
        typeof value === "string" || Buffer.isBuffer(value)
          ? value
          : json(value),
      );
    };
    const html = (value, headers) =>
      reply(200, value, "text/html; charset=utf-8", headers);
    try {
      requireValue(allowedHosts.has(req.headers.host), "Invalid Host", 403);
      const url = new URL(req.url, `http://${req.headers.host}`);
      const parts = url.pathname.split("/").slice(1);
      const method = req.method;
      if (method === "GET" && url.pathname === "/api/hub")
        return reply(200, {
          hub: true,
          version,
          pid: process.pid,
          port: origin && Number(new URL(origin).port),
          startedAt,
          live: active().length,
        });
      if (method === "GET" && url.pathname === "/api/sessions")
        return reply(200, { sessions: listed() });
      if (method === "GET" && url.pathname === "/") {
        const sessions = listed();
        const cookie = req.headers.cookie
          ?.split("; ")
          .find((item) => item.startsWith("interactive-plan-last="))
          ?.slice("interactive-plan-last=".length);
        const remembered = cookie && registry.get(cookie);
        const target =
          sessions.find((item) => item.needsYou)?.url ||
          (remembered?.state.current ? remembered.base + "/" : null) ||
          sessions[0]?.url;
        if (target) return reply(302, "", "text/plain", { Location: target });
        return html(
          '<!doctype html><title>Interactive plan</title><p style="font: 14px system-ui; margin: 40px">No live sessions.</p>',
        );
      }
      if (method === "POST" && url.pathname === "/agent/register") {
        requireValue(
          req.headers.authorization === `Bearer ${secret}`,
          "Hub secret required",
          403,
        );
        const data = await readBody(req, 10_000);
        requireValue(
          typeof data.sessionDir === "string" &&
            path.isAbsolute(data.sessionDir),
          "sessionDir must be an absolute path",
        );
        requireValue(
          data.wake &&
            typeof data.wake === "object" &&
            Object.values(harnesses).includes(data.wake.harness),
          "wake must name a harness: claude-code, codex, or copilot",
        );
        const directory = path.resolve(data.sessionDir);
        const session = await register(() => adopt(directory));
        await session.exclusive(() => session.setWake(data.wake));
        await atomic(path.join(directory, "connection.json"), {
          sessionId: session.id,
          origin,
          token: session.token,
          wake: { harness: data.wake.harness },
        });
        return reply(200, {
          sessionId: session.id,
          sessionDir: directory,
          url: origin + session.base + "/",
          wake: { harness: data.wake.harness },
          ...(hostOrigin ? { hostUrl: hostOrigin + session.base + "/" } : {}),
        });
      }
      if (parts[0] === "agent" && parts.length === 3) {
        const session = registry.get(parts[1]);
        requireValue(session, "Unknown session", 404);
        requireValue(
          req.headers.authorization === `Bearer ${session.token}`,
          "Agent token required",
          403,
        );
        if (method === "GET" && parts[2] === "next")
          return reply(
            200,
            await session.exclusive(async () => ({
              status: session.view(),
              event: (await session.pending())[0] || null,
            })),
          );
        if (method === "POST" && parts[2] === "action") {
          const data = await readBody(req, 10_000_000);
          return reply(200, await session.exclusive(() => session.act(data)));
        }
      }
      if (parts[0] === "s" && parts[1]) {
        const session = registry.get(parts[1]);
        requireValue(session, "Unknown session", 404);
        const rest = parts.slice(2);
        const revision = () => decodeURIComponent(rest[1]);
        if (method === "GET" && parts.length === 2)
          return reply(302, "", "text/plain", {
            Location: session.base + "/",
          });
        if (method === "GET" && rest.length === 1 && rest[0] === "") {
          if (!session.state.current)
            return reply(200, "No artifact published yet.", "text/plain");
          // Resolved under the session's directory, so a moved session
          // still serves its current revision. A session the reviewer closed
          // is read-only, so no tab left open on it can submit and wake an
          // agent that will never run again.
          return html(
            await artifactPage(
              session,
              session.revisionEntry(session.state.current.revision) ||
                session.state.current,
              session.state.dismissedAt ? { closed: true } : {},
            ),
            {
              "Set-Cookie": `interactive-plan-last=${session.id}; Path=/; SameSite=Strict; Max-Age=2592000`,
            },
          );
        }
        if (method === "GET" && rest[0] === "r" && rest.length === 2)
          return html(
            await artifactPage(session, session.revisionEntry(revision()), {
              readonly: true,
            }),
          );
        if (method === "GET" && rest[0] === "preview" && rest.length === 2)
          return html(
            await artifactPage(session, session.revisionEntry(revision()), {
              preview: true,
            }),
          );
        if (
          method === "GET" &&
          rest[0] === "r" &&
          rest[2] === "prototype" &&
          rest.length === 4
        ) {
          const prototype = await session.prototype(
            revision(),
            decodeURIComponent(rest[3]),
          );
          return html(prototype.html, {
            "Content-Security-Policy":
              "sandbox allow-scripts allow-forms allow-popups",
          });
        }
        if (method === "GET" && rest[0] === "api" && rest[1] === "status")
          return reply(200, session.view());
        if (method === "GET" && rest[0] === "api" && rest[1] === "page-set")
          return reply(200, session.pageSet(url.searchParams.get("revision")));
        if (method === "GET" && rest[0] === "api" && rest[1] === "page")
          return reply(
            200,
            await session.pageRecord(
              url.searchParams.get("revision"),
              url.searchParams.get("id"),
              url.searchParams.get("version"),
            ),
          );
        if (method === "GET" && rest[0] === "api" && rest[1] === "submission")
          return reply(200, {
            submission: await session.latestFeedback(
              url.searchParams.get("revision"),
            ),
          });
        if (method === "POST" && rest[0] === "api" && rest[1] === "dismiss") {
          requireValue(
            req.headers.origin === `http://${req.headers.host}`,
            "Unauthorized source",
            403,
          );
          return reply(200, await session.exclusive(() => session.dismiss()));
        }
        /* The hub is a local review tool. It binds 127.0.0.1 unless the
           operator sets INTERACTIVE_PLAN_HOST, and browser routes carry no
           token by design (see session.md), so the same-origin check is what
           stands between a page in another tab and this session. This route
           writes bytes, so it also caps the size and the count, decides the
           type from the leading bytes rather than a header, and names the
           file itself. */
        if (method === "POST" && rest[0] === "api" && rest[1] === "upload") {
          requireValue(
            req.headers.origin === `http://${req.headers.host}`,
            "Unauthorized source",
            403,
          );
          const bytes = await readBytes(req, uploadBytes);
          return reply(
            201,
            await session.exclusive(() => session.upload(bytes)),
          );
        }
        if (
          method === "POST" &&
          rest[0] === "api" &&
          rest[1] === "drawing-scene" &&
          rest.length === 2
        ) {
          requireValue(
            req.headers.origin === `http://${req.headers.host}`,
            "Unauthorized source",
            403,
          );
          const bytes = await readBytes(req, uploadBytes);
          return reply(
            201,
            await session.exclusive(() => session.uploadScene(bytes)),
          );
        }
        if (
          method === "GET" &&
          rest[0] === "api" &&
          rest[1] === "drawing-scene" &&
          rest.length === 3
        ) {
          const scene = await session.readScene(rest[2]);
          return reply(200, scene.bytes, "application/vnd.excalidraw+json");
        }
        /* The thumbnail in the note dialog, and the same image again after a
           reload: the draft keeps a reference and the bytes stay here. */
        if (
          method === "GET" &&
          rest[0] === "api" &&
          rest[1] === "upload" &&
          rest.length === 3
        ) {
          const image = await session.readUpload(rest[2]);
          return reply(200, image.bytes, image.type);
        }
        if (
          method === "DELETE" &&
          rest[0] === "api" &&
          rest[1] === "upload" &&
          rest.length === 3
        ) {
          requireValue(
            req.headers.origin === `http://${req.headers.host}`,
            "Unauthorized source",
            403,
          );
          return reply(
            200,
            await session.exclusive(() => session.removeUpload(rest[2])),
          );
        }
        if (method === "POST" && rest[0] === "api" && rest[1] === "feedback") {
          requireValue(
            req.headers.origin === `http://${req.headers.host}`,
            "Unauthorized source",
            403,
          );
          const data = await readBody(req, 250_000);
          return reply(
            200,
            await session.exclusive(() => session.submit(data)),
          );
        }
      }
      requireValue(false, "Not found", 404);
    } catch (error) {
      reply(
        error.statusCode ||
          (error.code === "ENOENT"
            ? 404
            : error instanceof SyntaxError
              ? 400
              : 500),
        { error: error.message },
      );
    }
  }
  const listen = (host, port) =>
    new Promise((resolve, reject) => {
      const server = http.createServer(handle);
      server.once("error", reject);
      server.listen(port, host, () => resolve(server));
    });
  const servers = [await listen("127.0.0.1", config.port)];
  const port = servers[0].address().port;
  origin = `http://127.0.0.1:${port}`;
  const hosts = ["127.0.0.1"];
  if (config.host) {
    try {
      servers.push(await listen(config.host, port));
    } catch (error) {
      servers[0].close();
      throw error;
    }
    hosts.push(config.host);
    hostOrigin = `http://${config.host}:${port}`;
  }
  allowedHosts = new Set(
    [...hosts, "localhost"].map((host) => `${host}:${port}`),
  );
  for (const name of await fs.readdir(config.sessions)) {
    const directory = path.join(config.sessions, name);
    if (!(await exists(path.join(directory, "status.json")))) continue;
    try {
      await adopt(directory);
    } catch (error) {
      log(`skipped session ${name}: ${error.message}`);
    }
  }
  await atomic(config.hubFile, {
    pid: process.pid,
    port,
    hosts,
    version,
    startedAt,
    secret,
  });
  let lastLiveAt = Date.now();
  let closing = false;
  let timer;
  const close = async () => {
    if (closing) return;
    closing = true;
    clearInterval(timer);
    for (const server of servers) {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
    try {
      if ((await read(config.hubFile)).pid === process.pid)
        await fs.rm(config.hubFile, { force: true });
    } catch {
      /* The record is already gone or belongs to a newer hub. */
    }
  };
  timer = setInterval(
    async () => {
      const now = Date.now();
      if (active().length) lastLiveAt = now;
      else if (now - lastLiveAt > config.idleMs) {
        log("no live sessions; exiting");
        await close();
        process.exit(0);
      }
    },
    Math.min(5000, Math.max(50, config.idleMs / 4)),
  );
  log(
    `hub ${version} listening on ${origin}${hostOrigin ? ` and ${hostOrigin}` : ""}`,
  );
  return { origin, hostOrigin, port, secret, close };
}

async function readRecord(config) {
  try {
    return await read(config.hubFile);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}
async function hubInfo(port) {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/api/hub`, {
      signal: AbortSignal.timeout(1500),
    });
    const info = await response.json();
    return info.hub === true ? info : null;
  } catch {
    return null;
  }
}
function processAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
}
const portOpen = (port) =>
  new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
async function waitFor(check, ms) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const result = await check();
    if (result) return result;
    await sleep(150);
  }
  return null;
}
async function spawnHub(config) {
  await fs.mkdir(config.hubDir, { recursive: true, mode: 0o700 });
  const log = await fs.open(config.hubLog, "a", 0o600);
  const child = spawn(process.execPath, [here, "hub"], {
    detached: true,
    stdio: ["ignore", log.fd, log.fd],
    cwd: os.homedir(),
  });
  child.unref();
  await log.close();
  const started = await waitFor(async () => {
    const record = await readRecord(config);
    if (record?.pid === child.pid) return hubInfo(record.port);
    return config.port ? hubInfo(config.port) : null;
  }, 15_000);
  requireValue(
    started,
    process.env.CODEX_SANDBOX
      ? `The hub did not start inside the sandbox (its log is ${config.hubLog}): ${sandboxAdvice()}`
      : `The hub did not start; see ${config.hubLog}`,
  );
  return started;
}
export async function ensureHub(config = settings()) {
  const record = await readRecord(config);
  const port = record?.port || config.port;
  let info = port ? await hubInfo(port) : null;
  if (!info && record && processAlive(record.pid))
    info = await waitFor(() => hubInfo(record.port), 5000);
  if (info && info.version !== version) {
    if (info.live === 0) {
      process.kill(info.pid, "SIGTERM");
      await waitFor(async () => !(await hubInfo(info.port)), 5000);
      info = null;
    } else
      console.error(
        `interactive-plan: the hub runs code version ${info.version}; this helper is ${version}. It restarts when no session is live.`,
      );
  }
  if (!info) {
    if (record) await fs.rm(config.hubFile, { force: true });
    requireValue(
      !(config.port && (await portOpen(config.port))),
      `Port ${config.port} is in use by another program; set INTERACTIVE_PLAN_PORT`,
    );
    info = await spawnHub(config);
  }
  return { ...info, origin: `http://127.0.0.1:${info.port}` };
}
export async function attach(
  directory,
  config = settings(),
  wake = detectWake(),
) {
  const hub = await ensureHub(config);
  const record = await readRecord(config);
  requireValue(
    record && record.pid === hub.pid,
    "The hub record is missing; stop the hub process and run start again",
  );
  const response = await fetch(hub.origin + "/agent/register", {
    method: "POST",
    headers: {
      authorization: `Bearer ${record.secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ sessionDir: directory, wake }),
    signal: AbortSignal.timeout(15000),
  });
  const result = await response.json();
  requireValue(response.ok, result.error || "Registration failed");
  return result;
}

// The source a revision was built from is kept beside the artifacts, so the
// next round starts from it after the temp directory is gone.
async function keepSource(sessionDir, source, html) {
  const record = pageData(html);
  const target = path.join(
    path.resolve(sessionDir),
    "src",
    record.revision,
    record.page.id,
  );
  await fs.mkdir(path.dirname(target), { recursive: true });
  try {
    await fs.mkdir(target);
  } catch (error) {
    requireValue(
      error.code !== "EEXIST",
      `Source for revision ${revision} already exists at ${target}`,
    );
    throw error;
  }
  await fs.cp(path.resolve(source), target, { recursive: true });
  return target;
}
// Codex sets CODEX_SANDBOX for every command, bypassed or not, so only a
// real refusal from the sandbox earns the advice.
const sandboxAdvice = () =>
  `run this command outside the sandbox (escalated), and run \`node ${path.join(path.dirname(here), "check.mjs")} --codex-rules\` once so an allow rule keeps Codex from asking again`;
export function withSandboxHint(message, env = process.env) {
  if (!env.CODEX_SANDBOX || !/\bEPERM\b/.test(message)) return message;
  return `${message}. The sandbox blocked it: ${sandboxAdvice()}`;
}
function argumentsFrom(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let i = 0; i < rest.length; i++) {
    requireValue(rest[i].startsWith("--"), "Options must use --name value");
    const key = rest[i].slice(2);
    requireValue(
      rest[i + 1] && !rest[i + 1].startsWith("--"),
      `Missing value for --${key}`,
    );
    options[key] = rest[++i];
  }
  return { command, options };
}
export async function main(argv) {
  requireValue(
    Number(process.versions.node.split(".")[0]) >= 20,
    "Node 20 or newer is required",
  );
  const { command, options } = argumentsFrom(argv);
  const config = settings();
  if (command === "hub") {
    const hub = await startHub(config);
    for (const signal of ["SIGTERM", "SIGINT"])
      process.once(signal, () => hub.close().then(() => process.exit(0)));
    return;
  }
  let directory =
    options["session-dir"] && path.resolve(options["session-dir"]);
  if (command === "start") {
    directory ||= path.join(config.sessions, crypto.randomUUID());
    return console.log(json(await attach(directory, config)));
  }
  requireValue(directory, "Every operation requires --session-dir PATH");
  const connectionFile = path.join(directory, "connection.json");
  if (!(await exists(connectionFile))) await attach(directory, config);
  let connection = await read(connectionFile);
  const checkConnection = () =>
    requireValue(
      /^http:\/\/127\.0\.0\.1:\d+$/.test(connection.origin),
      "Invalid connection origin",
    );
  checkConnection();
  async function request(route, data, retry = true) {
    const reattach = async () => {
      await attach(directory, config);
      connection = await read(connectionFile);
      checkConnection();
      return request(route, data, false);
    };
    let response;
    try {
      response = await fetch(connection.origin + route(connection.sessionId), {
        method: data ? "POST" : "GET",
        headers: {
          authorization: `Bearer ${connection.token}`,
          ...(data ? { "Content-Type": "application/json" } : {}),
        },
        ...(data
          ? {
              body: JSON.stringify({
                ...data,
                sessionId: connection.sessionId,
              }),
            }
          : {}),
        signal: AbortSignal.timeout(15000),
      });
    } catch (error) {
      if (retry && error.name === "TypeError") return reattach();
      throw error;
    }
    const result = await response.json();
    if (retry && response.status === 404 && result.error === "Unknown session")
      return reattach();
    requireValue(
      response.ok,
      result.error || "Request failed",
      response.status,
    );
    requireValue(
      (result.status?.sessionId || result.sessionId) === connection.sessionId,
      "Helper identity changed; resume the intended session",
      409,
    );
    return result;
  }
  if (command === "status")
    return console.log(json(await request((id) => `/s/${id}/api/status`)));
  const action = { action: command };
  if (command === "read") action.id = options.id;
  if (command === "pause") action.reason = options.reason;
  if (command === "progress") {
    requireValue(
      options.start && !options.pages && !options.steps && !options.done,
      "progress takes --start ID",
    );
    action.start = options.start.split("|");
  }
  let kept = null;
  if (command === "publish") {
    requireValue(options.file, "publish requires --file HTML");
    action.html = await fs.readFile(path.resolve(options.file), "utf8");
    if (options.pages)
      action.pages = (await read(path.resolve(options.pages))).pages;
    if (options.source) {
      kept = await keepSource(
        options["session-dir"],
        options.source,
        action.html,
      );
      action.source = kept;
    }
  }
  try {
    console.log(json(await request((id) => `/agent/${id}/action`, action)));
  } catch (error) {
    if (kept) await fs.rm(kept, { recursive: true, force: true });
    throw error;
  }
}
// Compare real paths: through the ~/.config symlink the two differ, and a
// guard on the spelling alone exits without running anything.
const invoked = (() => {
  try {
    return (
      process.argv[1] &&
      realpathSync(path.resolve(process.argv[1])) === realpathSync(here)
    );
  } catch {
    return false;
  }
})();
if (invoked) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`interactive-plan: ${withSandboxHint(error.message)}`);
    process.exitCode = 1;
  });
}
