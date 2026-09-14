#!/usr/bin/env node
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$/;
const revisionPattern = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$/;
const json = (value) => JSON.stringify(value, null, 2);
const exists = async (file) =>
  fs.access(file).then(
    () => true,
    () => false,
  );
const read = async (file) => JSON.parse(await fs.readFile(file, "utf8"));
const timestamp = () => new Date().toISOString();
function requireValue(condition, message, code = 400) {
  if (!condition) throw Object.assign(new Error(message), { statusCode: code });
}
async function atomic(file, value) {
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(temporary, json(value), { mode: 0o600 });
  await fs.rename(temporary, file);
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
  for (const page of data.pages) {
    requireValue(
      idPattern.test(page.id || "") &&
        page.id !== "feedback" &&
        !ids.has(page.id),
      "Page IDs must be unique; feedback is reserved",
    );
    requireValue(
      typeof page.title === "string" &&
        page.title.trim() &&
        typeof page.html === "string",
      "Pages require title and html",
    );
    ids.add(page.id);
  }
  requireValue(
    data.kind !== "plan" || data.pages[0].id === "overview",
    "A final plan starts with an overview page",
  );
  return data;
}

async function acquireLock(directory, recover) {
  const lock = path.join(directory, ".owner");
  if (recover && (await exists(lock))) {
    const owner = await read(path.join(lock, "owner.json"));
    requireValue(
      Number.isInteger(owner.pid) && owner.pid > 0,
      "Invalid owner record; inspect the session before recovery",
    );
    let alive = true;
    try {
      process.kill(owner.pid, 0);
    } catch (error) {
      if (error.code === "ESRCH") alive = false;
      else throw error;
    }
    requireValue(
      !alive,
      "The session owner is still running; do not recover its lock",
      409,
    );
    if (await exists(path.join(directory, "connection.json"))) {
      const connection = await read(path.join(directory, "connection.json"));
      requireValue(
        /^http:\/\/127\.0\.0\.1:\d+$/.test(connection.origin),
        "Invalid stored origin",
      );
      let reachable = false;
      try {
        await fetch(connection.origin + "/api/status", {
          signal: AbortSignal.timeout(1000),
        });
        reachable = true;
      } catch {
        /* A dead owner also needs an unreachable endpoint. */
      }
      requireValue(
        !reachable,
        "The old endpoint still responds; inspect it before recovery",
        409,
      );
    }
    await fs.unlink(path.join(lock, "owner.json"));
    await fs.rmdir(lock);
  }
  try {
    await fs.mkdir(lock, { mode: 0o700 });
  } catch (error) {
    if (error.code === "EEXIST")
      throw new Error(
        "Session already owned. After verifying the previous process stopped, use start --recover-lock with this session directory.",
      );
    throw error;
  }
  await atomic(path.join(lock, "owner.json"), {
    pid: process.pid,
    instance: crypto.randomUUID(),
    startedAt: timestamp(),
  });
  return async () => {
    await fs.unlink(path.join(lock, "owner.json"));
    await fs.rmdir(lock);
  };
}

export async function serve(directory, { recover = false } = {}) {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const release = await acquireLock(directory, recover);
  const stateFile = path.join(directory, "status.json");
  let server;
  try {
    for (const child of ["artifacts", "feedback"])
      await fs.mkdir(path.join(directory, child), {
        recursive: true,
        mode: 0o700,
      });
    let state = (await exists(stateFile))
      ? await read(stateFile)
      : {
          sessionId: crypto.randomUUID(),
          stage: "ready",
          current: null,
          acknowledged: [],
          question: null,
          accepted: null,
          updatedAt: timestamp(),
        };
    requireValue(
      idPattern.test(state.sessionId) && Array.isArray(state.acknowledged),
      "Invalid session state",
    );
    await atomic(stateFile, state);
    let serialized = Promise.resolve();
    const exclusive = (fn) => {
      const result = serialized.then(fn);
      serialized = result.catch(() => {});
      return result;
    };
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
    if ((await pending()).length)
      await transition({ stage: state.question ? "needs_reply" : "submitted" });
    const token = crypto.randomBytes(32).toString("hex");
    let origin;
    function sameArtifact(event) {
      return (
        state.current &&
        event.artifactId === state.current.artifactId &&
        event.revision === state.current.revision
      );
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
        ["feedback-only", "clarification-reply", "accept-plan"].includes(
          data.intent,
        ),
        "Invalid submission intent",
      );
      requireValue(
        data.groups &&
          typeof data.groups === "object" &&
          !Array.isArray(data.groups),
        "groups must be an object",
      );
      const file = path.join(directory, "feedback", data.id + ".json");
      if (await exists(file)) {
        const original = await read(file);
        requireValue(
          isDeepStrictEqual(original.payload, data),
          "Submission ID already has different content",
          409,
        );
        return { id: data.id, saved: true, status: state };
      }
      requireValue(
        sameArtifact(data),
        "Review the current artifact before submitting; export older drafts if needed",
        409,
      );
      if (data.intent === "clarification-reply")
        requireValue(
          state.stage === "needs_reply" &&
            data.questionId === state.question?.id,
          "This question is no longer awaiting a reply",
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
          "Resolve feedback and questions before accepting the current final plan",
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
          data.intent === "feedback-only" &&
          (state.stage === "working" || state.question)
            ? state.question
              ? "needs_reply"
              : "working"
            : "submitted",
        latestSubmissionId: data.id,
        accepted: null,
        ...(data.intent === "clarification-reply" ? { question: null } : {}),
      });
      return { id: data.id, saved: true, status: state };
    }
    async function act(data) {
      requireValue(data.sessionId === state.sessionId, "Wrong session", 409);
      if (data.action === "ack") {
        requireValue(idPattern.test(data.id || ""), "Submission ID required");
        if (state.acknowledged.includes(data.id)) return { status: state };
        const event = await read(
          path.join(directory, "feedback", data.id + ".json"),
        );
        const patch = {
          stage: state.question ? "needs_reply" : "working",
          acknowledged: [...state.acknowledged, data.id],
          acknowledgedAt: timestamp(),
          lastAcknowledgedId: data.id,
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
        return { status: await transition(patch), event };
      }
      if (data.action === "question") {
        requireValue(
          state.current && typeof data.text === "string" && data.text.trim(),
          "Publish an artifact and provide question text",
        );
        requireValue(
          !(await pending()).length,
          "Read pending feedback before asking another question",
          409,
        );
        return {
          status: await transition({
            stage: "needs_reply",
            question: { id: crypto.randomUUID(), text: data.text },
            accepted: null,
          }),
        };
      }
      if (data.action === "working")
        return {
          status: await transition({ stage: "working", question: null }),
        };
      if (data.action === "publish") {
        requireValue(
          !state.question && !(await pending()).length,
          "Resolve the question and read pending feedback before publishing",
          409,
        );
        requireValue(typeof data.html === "string", "HTML is required");
        const artifact = artifactData(data.html);
        const name = `${artifact.artifactId}.${artifact.revision}.html`;
        const file = path.join(directory, "artifacts", name);
        requireValue(
          !(await exists(file)),
          "Artifact revision already exists; choose a new revision",
          409,
        );
        const config = json({ sessionId: state.sessionId, origin }).replaceAll(
          "<",
          "\\u003c",
        );
        const configScript =
          /(<script\b(?=[^>]*\bid=["']session-config["'])[^>]*>)[\s\S]*?(<\/script>)/i;
        requireValue(
          configScript.test(data.html),
          "HTML requires a session-config JSON script",
        );
        const html = data.html.replace(configScript, `$1${config}$2`);
        const temporary = file + ".tmp";
        await fs.writeFile(temporary, html, { mode: 0o600, flag: "wx" });
        await fs.rename(temporary, file);
        const current = {
          artifactId: artifact.artifactId,
          revision: artifact.revision,
          kind: artifact.kind,
          title: artifact.title,
          path: file,
          url: "/artifacts/" + name,
          sha256: crypto.createHash("sha256").update(html).digest("hex"),
        };
        return {
          status: await transition({
            stage: "updated",
            current,
            question: null,
            accepted: null,
          }),
          url: origin + current.url,
        };
      }
      if (data.action === "complete") {
        requireValue(
          state.accepted &&
            state.accepted.sha256 === state.current?.sha256 &&
            !(await pending()).length &&
            !state.question,
          "Acknowledge acceptance of the current plan before completing",
          409,
        );
        return {
          status: await transition({ stage: "complete" }),
          planPath: state.accepted.path,
          nextAction:
            state.accepted.mode === "implement" ? "implement" : "save",
        };
      }
      throw new Error("Unknown agent action");
    }
    server = http.createServer(async (req, res) => {
      const reply = (code, value, type = "application/json") => {
        res.writeHead(code, {
          "Content-Type": type,
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
        });
        res.end(
          typeof value === "string" || Buffer.isBuffer(value)
            ? value
            : json(value),
        );
      };
      try {
        requireValue(
          req.headers.host === new URL(origin).host,
          "Invalid Host",
          403,
        );
        const url = new URL(req.url, origin);
        if (req.method === "GET" && url.pathname === "/api/status")
          return reply(200, state);
        if (req.method === "GET" && url.pathname === "/agent/next") {
          requireValue(
            req.headers.authorization === `Bearer ${token}`,
            "Agent token required",
            403,
          );
          return reply(
            200,
            await exclusive(async () => ({
              status: state,
              event: (await pending())[0] || null,
            })),
          );
        }
        if (
          req.method === "GET" &&
          (url.pathname === "/" || url.pathname.startsWith("/artifacts/"))
        ) {
          if (!state.current)
            return reply(200, "No artifact published yet.", "text/plain");
          const name =
            url.pathname === "/"
              ? path.basename(state.current.path)
              : url.pathname.slice(11);
          requireValue(
            /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,170}\.html$/.test(name),
            "Invalid artifact path",
            404,
          );
          return reply(
            200,
            await fs.readFile(path.join(directory, "artifacts", name)),
            "text/html; charset=utf-8",
          );
        }
        requireValue(
          req.method === "POST" &&
            ["/api/feedback", "/agent/action"].includes(url.pathname),
          "Not found",
          404,
        );
        const agent = url.pathname === "/agent/action";
        requireValue(
          agent
            ? req.headers.authorization === `Bearer ${token}`
            : req.headers.origin === origin,
          "Unauthorized source",
          403,
        );
        requireValue(
          req.headers["content-type"] === "application/json",
          "JSON required",
          415,
        );
        let raw = "";
        for await (const chunk of req) {
          raw += chunk;
          requireValue(
            Buffer.byteLength(raw) <= (agent ? 10_000_000 : 250_000),
            "Request too large",
            413,
          );
        }
        const data = JSON.parse(raw);
        reply(200, await exclusive(() => (agent ? act(data) : submit(data))));
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
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    origin = `http://127.0.0.1:${server.address().port}`;
    await atomic(path.join(directory, "connection.json"), {
      sessionId: state.sessionId,
      origin,
      token,
    });
    console.log(
      json({
        sessionId: state.sessionId,
        sessionDir: directory,
        origin,
        currentUrl: state.current ? origin + state.current.url : null,
      }),
    );
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      await new Promise((resolve) => server.close(resolve));
      await serialized;
      await release();
    };
    return { close, origin, sessionId: state.sessionId };
  } catch (error) {
    server?.close();
    await release();
    throw error;
  }
}

function argumentsFrom(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let i = 0; i < rest.length; i++) {
    requireValue(rest[i].startsWith("--"), "Options must use --name value");
    const key = rest[i].slice(2);
    if (key === "recover-lock") options[key] = true;
    else {
      requireValue(
        rest[i + 1] && !rest[i + 1].startsWith("--"),
        `Missing value for --${key}`,
      );
      options[key] = rest[++i];
    }
  }
  return { command, options };
}
export async function main(argv) {
  requireValue(
    Number(process.versions.node.split(".")[0]) >= 20,
    "Node 20 or newer is required",
  );
  const { command, options } = argumentsFrom(argv);
  let directory =
    options["session-dir"] && path.resolve(options["session-dir"]);
  if (command === "start") {
    directory ||= path.join(
      process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state"),
      "plan-interactively",
      "sessions",
      crypto.randomUUID(),
    );
    const session = await serve(directory, {
      recover: options["recover-lock"] === true,
    });
    for (const signal of ["SIGTERM", "SIGINT"])
      process.once(signal, () => session.close().then(() => process.exit(0)));
    return;
  }
  requireValue(directory, "Every operation requires --session-dir PATH");
  const connection = await read(path.join(directory, "connection.json"));
  requireValue(
    /^http:\/\/127\.0\.0\.1:\d+$/.test(connection.origin),
    "Invalid connection origin",
  );
  async function request(route, data) {
    const response = await fetch(connection.origin + route, {
      method: data ? "POST" : "GET",
      headers: {
        authorization: `Bearer ${connection.token}`,
        ...(data ? { "Content-Type": "application/json" } : {}),
      },
      ...(data
        ? { body: JSON.stringify({ ...data, sessionId: connection.sessionId }) }
        : {}),
      signal: AbortSignal.timeout(15000),
    });
    const result = await response.json();
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
    return console.log(json(await request("/api/status")));
  if (command === "wait") {
    const seconds = Number(options.timeout || 55);
    requireValue(
      Number.isFinite(seconds) && seconds > 0 && seconds <= 3600,
      "timeout must be between 0 and 3600 seconds",
    );
    const deadline = Date.now() + seconds * 1000;
    while (Date.now() < deadline) {
      const result = await request("/agent/next");
      if (result.event) return console.log(json(result));
      await new Promise((resolve) =>
        setTimeout(resolve, Math.min(1000, deadline - Date.now())),
      );
    }
    return console.log(
      json({ waiting: true, sessionId: connection.sessionId }),
    );
  }
  const action = { action: command };
  if (command === "ack") action.id = options.id;
  if (command === "question") action.text = options.text;
  if (command === "publish") {
    requireValue(options.file, "publish requires --file HTML");
    action.html = await fs.readFile(path.resolve(options.file), "utf8");
  }
  console.log(json(await request("/agent/action", action)));
}
if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`plan-interactively: ${error.message}`);
    process.exitCode = 1;
  });
}
