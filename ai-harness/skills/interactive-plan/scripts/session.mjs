#!/usr/bin/env node
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import { readFileSync, realpathSync } from "node:fs";
import fs from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { choiceText } from "../assets/choices.mjs";

const here = fileURLToPath(import.meta.url);
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
    disconnectMs: seconds("INTERACTIVE_PLAN_DISCONNECT_SECONDS", 900) * 1000,
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
    Array.isArray(data.pages) && data.pages.length > 0,
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
        page.id !== "feedback" &&
        !(page.id === "agreed" && data.agreements !== undefined) &&
        !ids.has(page.id),
      "Page IDs must be unique; feedback and structured agreed are reserved",
    );
    requireValue(
      typeof page.title === "string" &&
        page.title.trim() &&
        typeof page.html === "string",
      "Pages require title and html",
    );
    ids.add(page.id);
  }
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
    data.kind !== "plan" || data.pages[0].id === "overview",
    "A final plan starts with an overview page",
  );
  return data;
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
  for (const child of ["artifacts", "feedback"])
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
        progress: null,
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
  let agentSeenAt = Date.parse(state.agentSeenAt || "") || 0;
  let seenWrittenAt = agentSeenAt;
  const seenText = () =>
    agentSeenAt ? new Date(agentSeenAt).toISOString() : null;
  const transition = async (patch) => {
    state = {
      ...state,
      ...patch,
      agentSeenAt: seenText(),
      updatedAt: timestamp(),
    };
    seenWrittenAt = agentSeenAt;
    await atomic(stateFile, state);
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
    Boolean(state.current) && ["ready", "updated"].includes(state.stage);
  const live = (now) =>
    state.stage !== "complete" && now - agentSeenAt < config.disconnectMs;
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
    if (data.groups.answers !== undefined) {
      requireValue(
        data.groups.answers &&
          typeof data.groups.answers === "object" &&
          !Array.isArray(data.groups.answers),
        "answers must be an object",
      );
      for (const answer of Object.values(data.groups.answers))
        requireValue(
          answer &&
            ["label", "text", "topic"].every(
              (key) => typeof answer[key] === "string",
            ) &&
            answer.text.trim(),
          "Answers require label, text, and topic",
        );
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
        ["save", "implement"].includes(data.mode),
        "Choose save or implement explicitly",
      );
      requireValue(
        state.current.kind === "plan" &&
          ["ready", "updated"].includes(state.stage) &&
          !(await pending()).length,
        "Resolve feedback before accepting the current final plan",
        409,
      );
    }
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
      accepted: null,
    });
    return { id: data.id, saved: true, status: view() };
  }
  async function publish(html) {
    requireValue(
      !(await pending()).length,
      "Read pending feedback before publishing",
      409,
    );
    requireValue(typeof html === "string", "HTML is required");
    const artifact = artifactData(html);
    const submissions = await events();
    for (const entry of artifact.agreements || []) {
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
        const payload = event.payload;
        const item = sourceItem(payload, ref);
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
        requireValue(
          idPattern.test(payload.artifactId || "") &&
            revisionPattern.test(payload.revision || ""),
          "Invalid source artifact",
        );
        const target =
          typeof item.target === "string" && idPattern.test(item.target)
            ? item.target
            : null;
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
    const name = `${artifact.artifactId}.${artifact.revision}.html`;
    const file = path.join(directory, "artifacts", name);
    requireValue(
      !(await exists(file)),
      "Artifact revision already exists; choose a new revision",
      409,
    );
    requireValue(
      configScript.test(html),
      "HTML requires a session-config JSON script",
    );
    const stored = embedConfig(html, {
      sessionId: state.sessionId,
      base,
    }).replace(
      /(<script\b(?=[^>]*\bid=["']plan-data["'])[^>]*>)[\s\S]*?(<\/script>)/i,
      (_, start, end) =>
        start + json(artifact).replaceAll("<", "\\u003c") + end,
    );
    const temporary = file + ".tmp";
    await fs.writeFile(temporary, stored, { mode: 0o600, flag: "wx" });
    await fs.rename(temporary, file);
    const current = {
      artifactId: artifact.artifactId,
      revision: artifact.revision,
      kind: artifact.kind,
      title: artifact.title,
      path: file,
      url: base + "/",
      sha256: crypto.createHash("sha256").update(stored).digest("hex"),
      publishedAt: timestamp(),
    };
    const revisions = [
      ...(state.revisions || []),
      {
        artifactId: current.artifactId,
        revision: current.revision,
        kind: current.kind,
        title: current.title,
        publishedAt: current.publishedAt,
        url: `${base}/r/${encodeURIComponent(current.revision)}`,
      },
    ];
    await transition({
      stage: "updated",
      current,
      title: current.title,
      kind: current.kind,
      revisions,
      accepted: null,
      progress: null,
    });
    return { status: view(), url: origin + current.url };
  }
  async function act(data) {
    requireValue(data.sessionId === state.sessionId, "Wrong session", 409);
    if (data.action === "ack") {
      requireValue(idPattern.test(data.id || ""), "Submission ID required");
      if (state.acknowledged.includes(data.id)) return { status: view() };
      const event = await read(
        path.join(directory, "feedback", data.id + ".json"),
      );
      const patch = {
        stage: "working",
        acknowledged: [...state.acknowledged, data.id],
        acknowledgedAt: timestamp(),
        lastAcknowledgedId: data.id,
        progress: null,
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
          acceptedAt: event.receivedAt,
        };
        await atomic(path.join(directory, "acceptance.json"), patch.accepted);
      }
      await transition(patch);
      return { status: view(), event };
    }
    if (data.action === "working") {
      await transition({ stage: "working" });
      return { status: view() };
    }
    if (data.action === "progress") {
      requireValue(
        state.stage === "working",
        "Acknowledge feedback before reporting progress",
        409,
      );
      const given = ["steps", "start", "done"].filter(
        (key) => data[key] !== undefined,
      );
      requireValue(
        given.length === 1,
        "progress requires exactly one of steps, start, or done",
      );
      if (data.steps !== undefined) {
        requireValue(
          Array.isArray(data.steps) &&
            data.steps.length > 0 &&
            data.steps.length <= 12,
          "progress requires 1 to 12 steps",
        );
        const titles = data.steps.map((title) =>
          typeof title === "string" ? title.trim() : "",
        );
        requireValue(
          titles.every((title) => title && title.length <= 80) &&
            new Set(titles).size === titles.length,
          "Step titles must be unique, non-empty, and at most 80 characters",
        );
        await transition({
          progress: {
            steps: titles.map((title) => ({ title, state: "pending" })),
            updatedAt: timestamp(),
          },
        });
        return { status: view() };
      }
      requireValue(state.progress, "Declare steps before marking one");
      // Steps are a set: several can be active at once, in any order.
      const named = data.start !== undefined ? data.start : [data.done];
      requireValue(
        Array.isArray(named) &&
          named.length > 0 &&
          named.every((title) => typeof title === "string"),
        data.start !== undefined
          ? "progress start requires step titles"
          : "progress done requires a step title",
      );
      const titles = named.map((title) => title.trim());
      for (const title of titles)
        requireValue(
          state.progress.steps.some((step) => step.title === title),
          "Unknown progress step",
        );
      const next = data.start !== undefined ? "active" : "done";
      await transition({
        progress: {
          steps: state.progress.steps.map((step) =>
            titles.includes(step.title) ? { ...step, state: next } : step,
          ),
          updatedAt: timestamp(),
        },
      });
      return { status: view() };
    }
    if (data.action === "publish") return publish(data.html);
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
      };
    }
    requireValue(false, "Unknown agent action");
  }
  function view(now = Date.now()) {
    return {
      ...state,
      agentSeenAt: seenText(),
      revisions: state.revisions || [],
      progress: state.progress || null,
      disconnected: state.stage !== "complete" && !live(now),
      needsYou: needsYou(),
    };
  }
  function listing(now = Date.now()) {
    if (!state.current) return null;
    return {
      id: state.sessionId,
      title: state.current.title,
      kind: state.current.kind,
      revision: state.current.revision,
      stage: state.stage,
      needsYou: needsYou(),
      agentSeenAt: seenText(),
      publishedAt: state.current.publishedAt,
      updatedAt: state.updatedAt,
      url: base + "/",
      live: live(now),
    };
  }
  async function persistSeen(force = false) {
    if (agentSeenAt === seenWrittenAt) return;
    if (!force && agentSeenAt - seenWrittenAt < 30_000) return;
    state = { ...state, agentSeenAt: seenText() };
    seenWrittenAt = agentSeenAt;
    await atomic(stateFile, state);
  }
  function touch() {
    agentSeenAt = Date.now();
    return exclusive(() => persistSeen());
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
    act,
    view,
    listing,
    live,
    touch,
    persistSeen,
    revisionEntry,
  };
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
  const live = (now = Date.now()) =>
    [...registry.values()].filter((session) => session.live(now));
  const listed = (now = Date.now()) =>
    live(now)
      .map((session) => session.listing(now))
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
          live: live().length,
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
        const directory = path.resolve(data.sessionDir);
        const session = await register(() => adopt(directory));
        await session.touch();
        await atomic(path.join(directory, "connection.json"), {
          sessionId: session.id,
          origin,
          token: session.token,
        });
        return reply(200, {
          sessionId: session.id,
          sessionDir: directory,
          url: origin + session.base + "/",
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
        await session.touch();
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
          return html(await artifactPage(session, session.state.current), {
            "Set-Cookie": `interactive-plan-last=${session.id}; Path=/; SameSite=Strict; Max-Age=2592000`,
          });
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
          const entry = session.revisionEntry(revision());
          requireValue(entry, "Unknown revision", 404);
          const data = artifactData(await fs.readFile(entry.path, "utf8"));
          const prototype = data.prototypes?.find(
            (item) => item.id === decodeURIComponent(rest[3]),
          );
          requireValue(prototype, "Unknown prototype", 404);
          return html(prototype.html, {
            "Content-Security-Policy":
              "sandbox allow-scripts allow-forms allow-popups",
          });
        }
        if (method === "GET" && rest[0] === "api" && rest[1] === "status")
          return reply(200, session.view());
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
    for (const session of registry.values())
      await session.exclusive(() => session.persistSeen(true));
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
      if (live(now).length) lastLiveAt = now;
      else if (now - lastLiveAt > config.idleMs) {
        log("no live sessions; exiting");
        await close();
        process.exit(0);
      }
      for (const session of registry.values())
        void session.exclusive(() => session.persistSeen());
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
  requireValue(started, `The hub did not start; see ${config.hubLog}`);
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
export async function attach(directory, config = settings()) {
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
    body: JSON.stringify({ sessionDir: directory }),
    signal: AbortSignal.timeout(15000),
  });
  const result = await response.json();
  requireValue(response.ok, result.error || "Registration failed");
  return result;
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
  if (command === "wait") {
    const seconds = Number(options.timeout || 55);
    requireValue(
      Number.isFinite(seconds) && seconds > 0 && seconds <= 3600,
      "timeout must be between 0 and 3600 seconds",
    );
    const deadline = Date.now() + seconds * 1000;
    while (Date.now() < deadline) {
      const result = await request((id) => `/agent/${id}/next`);
      if (result.event) return console.log(json(result));
      await sleep(Math.max(0, Math.min(1000, deadline - Date.now())));
    }
    return console.log(
      json({ waiting: true, sessionId: connection.sessionId }),
    );
  }
  const action = { action: command };
  if (command === "ack") action.id = options.id;
  if (command === "progress") {
    const given = ["steps", "start", "done"].filter(
      (key) => options[key] !== undefined,
    );
    requireValue(
      given.length === 1,
      "progress requires exactly one of --steps, --start, or --done",
    );
    if (options.steps !== undefined) action.steps = options.steps.split("|");
    else if (options.start !== undefined)
      action.start = options.start.split("|");
    else action.done = options.done;
  }
  if (command === "publish") {
    requireValue(options.file, "publish requires --file HTML");
    action.html = await fs.readFile(path.resolve(options.file), "utf8");
  }
  console.log(json(await request((id) => `/agent/${id}/action`, action)));
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
    console.error(`interactive-plan: ${error.message}`);
    process.exitCode = 1;
  });
}
