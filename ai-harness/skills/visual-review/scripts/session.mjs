#!/usr/bin/env node
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const assets = path.join(here, "..", "assets");
const json = (value) => JSON.stringify(value, null, 2);
const timestamp = () => new Date().toISOString();
const exists = async (file) =>
  fs.access(file).then(
    () => true,
    () => false,
  );
const read = async (file) => JSON.parse(await fs.readFile(file, "utf8"));
const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$/;

/** Reject a request with an HTTP status the route handler passes through. */
function requireValue(condition, message, code = 400) {
  if (!condition) throw Object.assign(new Error(message), { statusCode: code });
}

async function atomic(file, value) {
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(temporary, json(value), { mode: 0o600 });
  await fs.rename(temporary, file);
}

// Limits from the plan's scale rules. The path index gets its own ceiling
// because it is built once per ref and holds every tracked path, while a route
// response holds one file or one directory.
const FILE_LIMIT = 2 * 1024 * 1024;
const RESPONSE_LIMIT = 4 * 1024 * 1024;
const INDEX_LIMIT = 32 * 1024 * 1024;
const BINARY_PROBE = 8 * 1024;
const GIT_TIMEOUT = 10_000;
const FETCH_TIMEOUT = 30_000;
const CONCURRENCY = 8;

const refPattern = /^[A-Za-z0-9._/-]+$/;

/**
 * git reads GIT_DIR, GIT_WORK_TREE, and GIT_INDEX_FILE from the environment.
 * A helper started from a git hook would inherit them and answer about that
 * repository instead of the one it was pointed at, so they are dropped.
 */
export function gitEnvironment(source = process.env) {
  return Object.fromEntries(
    Object.entries(source).filter(([name]) => !name.startsWith("GIT_")),
  );
}

/**
 * Run git with a byte ceiling instead of a buffer: a file larger than the
 * ceiling is truncated at it rather than failing the request, and at most
 * CONCURRENCY subprocesses exist at once.
 */
export function createGit(root) {
  const env = gitEnvironment();
  let active = 0;
  const queue = [];
  const release = () => {
    active -= 1;
    queue.shift()?.();
  };
  const slot = () =>
    active < CONCURRENCY
      ? ((active += 1), Promise.resolve())
      : new Promise((resolve) =>
          queue.push(() => {
            active += 1;
            resolve();
          }),
        );
  return async function git(
    args,
    { timeout = GIT_TIMEOUT, cap = RESPONSE_LIMIT } = {},
  ) {
    await slot();
    try {
      return await new Promise((resolve, reject) => {
        const child = spawn("git", args, {
          cwd: root,
          env,
          stdio: ["ignore", "pipe", "pipe"],
        });
        const out = [];
        const errors = [];
        let size = 0;
        let truncated = false;
        let settled = false;
        let timer;
        const finish = (error, value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          child.kill("SIGKILL");
          if (error) reject(error);
          else resolve(value);
        };
        timer = setTimeout(
          () =>
            finish(
              Object.assign(new Error(`git ${args[0]} timed out`), {
                statusCode: 500,
              }),
            ),
          timeout,
        );
        child.stdout.on("data", (chunk) => {
          if (size >= cap) return;
          const room = cap - size;
          out.push(chunk.length > room ? chunk.subarray(0, room) : chunk);
          size += Math.min(chunk.length, room);
          if (size >= cap) {
            truncated = true;
            child.stdout.destroy();
          }
        });
        child.stderr.on("data", (chunk) => {
          if (errors.length < 64) errors.push(chunk);
        });
        child.on("error", (error) =>
          finish(
            error.code === "ENOENT"
              ? Object.assign(new Error("git is not on the PATH"), {
                  statusCode: 500,
                })
              : error,
          ),
        );
        child.on("close", (code) => {
          const stdout = Buffer.concat(out);
          const stderr = Buffer.concat(errors).toString("utf8").trim();
          // A process killed after the ceiling reports failure; the bytes
          // collected before the kill are the answer the caller asked for.
          if (code === 0 || truncated) finish(null, { stdout, truncated });
          else
            finish(
              Object.assign(new Error(stderr || `git ${args[0]} failed`), {
                statusCode: 500,
                stderr,
              }),
            );
        });
      });
    } finally {
      release();
    }
  };
}

/** Repository-relative posix path, or a rejection explaining the refusal. */
export function normalizePath(input) {
  const value = String(input ?? "");
  requireValue(!value.includes("\\"), "Paths use forward slashes");
  requireValue(!value.startsWith("/"), "Paths are repository-relative");
  requireValue(
    !/(^|\/)\.\.(\/|$)/.test(value),
    "Paths cannot escape the repository",
  );
  requireValue(!value.startsWith("-"), "Paths cannot start with a dash");
  const clean = value.replace(/\/+/g, "/").replace(/\/$/, "");
  requireValue(
    !clean.split("/").includes("."),
    "Paths cannot contain '.' segments",
  );
  return clean;
}

export function normalizeRef(input) {
  const value = String(input ?? "").trim();
  requireValue(value.length > 0 && value.length <= 255, "A ref is required");
  requireValue(refPattern.test(value), "Invalid ref");
  requireValue(!value.startsWith("-"), "Refs cannot start with a dash");
  return value;
}

const pullRequestRef = /^pr\/([1-9][0-9]{0,9})$/;

/**
 * The repository layer. Every answer comes from committed content at a
 * resolved commit, so the working tree, untracked files, and ignored
 * directories are invisible to it.
 */
export function createRepository({ root, git, cacheDir }) {
  const memory = new Map();
  const cacheFile = (key) =>
    path.join(
      cacheDir,
      crypto.createHash("sha256").update(key).digest("hex") + ".json",
    );

  async function cached(key, produce) {
    if (memory.has(key)) return memory.get(key);
    const task = (async () => {
      const file = cacheFile(key);
      if (await exists(file)) return (await read(file)).value;
      const value = await produce();
      await atomic(file, { key, value, storedAt: timestamp() });
      return value;
    })();
    memory.set(key, task);
    return task.catch((error) => {
      memory.delete(key);
      throw error;
    });
  }

  async function fetchPullRequest(number) {
    const target = `refs/visual-review/pr/${number}`;
    const known = await git(
      ["rev-parse", "--verify", "--quiet", `${target}^{commit}`],
      {
        cap: 4096,
      },
    ).catch(() => null);
    if (known?.stdout.length) return target;
    try {
      await git(["fetch", "origin", `pull/${number}/head:${target}`], {
        timeout: FETCH_TIMEOUT,
        cap: 64 * 1024,
      });
    } catch (error) {
      throw Object.assign(
        new Error(error.stderr || `Could not fetch pull request ${number}`),
        { statusCode: 502 },
      );
    }
    return target;
  }

  const resolutions = new Map();
  /** Resolve a ref to a commit sha, fetching a pull request head on first use. */
  async function resolve(input) {
    const ref = normalizeRef(input);
    if (resolutions.has(ref)) return resolutions.get(ref);
    const task = (async () => {
      const pull = ref.match(pullRequestRef);
      const target = pull ? await fetchPullRequest(pull[1]) : ref;
      const result = await git(
        ["rev-parse", "--verify", "--quiet", `${target}^{commit}`],
        { cap: 4096 },
      ).catch(() => ({ stdout: Buffer.alloc(0) }));
      const sha = result.stdout.toString("utf8").trim();
      requireValue(/^[0-9a-f]{40}$/.test(sha), `Unknown ref: ${ref}`, 404);
      return sha;
    })();
    resolutions.set(ref, task);
    return task.catch((error) => {
      resolutions.delete(ref);
      throw error;
    });
  }

  /** Every tracked path at a commit, built once and reused for search and existence. */
  async function index(sha) {
    return cached(`index:${sha}`, async () => {
      const { stdout, truncated } = await git(
        ["ls-tree", "-r", "--name-only", "-z", sha],
        { cap: INDEX_LIMIT },
      );
      requireValue(
        !truncated,
        "The repository index exceeds the supported size",
        507,
      );
      const paths = stdout.toString("utf8").split("\0").filter(Boolean);
      paths.sort();
      return paths;
    });
  }

  async function file(input, refInput) {
    const target = normalizePath(input);
    requireValue(target.length > 0, "A path is required");
    const ref = normalizeRef(refInput);
    const sha = await resolve(ref);
    const paths = await index(sha);
    requireValue(
      paths.includes(target),
      `No such file at ${ref}: ${target}`,
      404,
    );
    const value = await cached(`file:${sha}:${target}`, async () => {
      const { stdout, truncated } = await git(["show", `${sha}:${target}`], {
        cap: FILE_LIMIT,
      });
      requireValue(
        !stdout.subarray(0, BINARY_PROBE).includes(0),
        "Binary files are not served",
        415,
      );
      return { sha, content: stdout.toString("utf8"), truncated };
    });
    return { path: target, ref, ...value };
  }

  async function tree(input, refInput) {
    const target = normalizePath(input ?? "");
    const ref = normalizeRef(refInput);
    const sha = await resolve(ref);
    const value = await cached(`tree:${sha}:${target}`, async () => {
      const spec = target ? `${sha}:${target}` : sha;
      const { stdout } = await git(["ls-tree", "-z", spec]);
      const entries = stdout
        .toString("utf8")
        .split("\0")
        .filter(Boolean)
        .map((line) => {
          const [meta, name] = line.split("\t");
          const type = meta.split(" ")[1];
          return { name, type: type === "tree" ? "directory" : "file" };
        })
        .filter((entry) => entry.type === "directory" || entry.type === "file");
      // Directories first, then case-insensitive by name. The lowercase
      // comparison is explicit rather than locale-aware so two machines list
      // the same directory in the same order.
      const order = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
      entries.sort(
        (a, b) =>
          (a.type === "directory" ? 0 : 1) - (b.type === "directory" ? 0 : 1) ||
          order(a.name.toLowerCase(), b.name.toLowerCase()) ||
          order(a.name, b.name),
      );
      return entries;
    });
    return { path: target, ref, entries: value };
  }

  async function paths(refInput, query, limit) {
    const ref = normalizeRef(refInput);
    const sha = await resolve(ref);
    const all = await index(sha);
    const size = Math.min(Math.max(Number(limit) || 50, 1), 200);
    const needle = String(query ?? "").toLowerCase();
    if (!needle) return { ref, total: all.length, matches: all.slice(0, size) };
    const matches = [];
    let total = 0;
    for (const candidate of all) {
      if (!candidate.toLowerCase().includes(needle)) continue;
      total += 1;
      if (matches.length < size) matches.push(candidate);
    }
    return { ref, total, matches };
  }

  async function entry(input, refInput) {
    const target = normalizePath(input ?? "");
    const ref = normalizeRef(refInput);
    const sha = await resolve(ref);
    const all = await index(sha);
    if (!target) return { path: target, ref, exists: true, type: "directory" };
    if (all.includes(target))
      return { path: target, ref, exists: true, type: "file" };
    const prefix = target + "/";
    const directory = all.some((candidate) => candidate.startsWith(prefix));
    return {
      path: target,
      ref,
      exists: directory,
      type: directory ? "directory" : null,
    };
  }

  async function diff(baseInput, headInput, pathInput) {
    const target = pathInput === undefined ? null : normalizePath(pathInput);
    const base = normalizeRef(baseInput);
    const head = normalizeRef(headInput);
    const [baseSha, headSha] = await Promise.all([
      resolve(base),
      resolve(head),
    ]);
    const patch = await cached(
      `diff:${baseSha}..${headSha}:${target ?? ""}`,
      async () => {
        const args = [
          "diff",
          "--no-color",
          "--no-ext-diff",
          "--no-textconv",
          `${baseSha}..${headSha}`,
        ];
        if (target) args.push("--", target);
        const { stdout } = await git(args);
        return stdout.toString("utf8");
      },
    );
    return { base, head, path: target, patch };
  }

  return { resolve, index, file, tree, paths, entry, diff, cacheFile };
}

/** Repository identity: where it is, what it is called, and which ref it opens on. */
export async function describeRepository(git, root) {
  const branch = (
    await git(["rev-parse", "--abbrev-ref", "HEAD"], { cap: 4096 })
  ).stdout
    .toString("utf8")
    .trim();
  const head = (await git(["rev-parse", "HEAD"], { cap: 4096 })).stdout
    .toString("utf8")
    .trim();
  const origin = await git(["remote", "get-url", "origin"], { cap: 4096 })
    .then((result) => result.stdout.toString("utf8").trim())
    .catch(() => "");
  const slug = origin.match(/([^/:]+\/[^/]+?)(?:\.git)?$/);
  return {
    root,
    name: slug ? slug[1] : path.basename(root),
    ref: branch === "HEAD" ? head : branch,
    refType: branch === "HEAD" ? "commit" : "branch",
    head,
  };
}

const pageIdPattern = /^[a-z0-9][a-z0-9-]{0,39}$/;

/** Parse `id=Title,id=Title` into the outline the agent declared. */
export function parsePages(spec) {
  const pages = String(spec ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separator = entry.indexOf("=");
      requireValue(separator > 0, `Each page is id=Title: ${entry}`);
      const id = entry.slice(0, separator).trim();
      const title = entry.slice(separator + 1).trim();
      requireValue(pageIdPattern.test(id), `Invalid page id: ${id}`);
      requireValue(title.length > 0, `Page ${id} needs a title`);
      return { id, title, status: "planned" };
    });
  requireValue(pages.length > 0, "A plan needs at least one page");
  const ids = new Set();
  for (const page of pages) {
    requireValue(!ids.has(page.id), `Duplicate page id: ${page.id}`);
    ids.add(page.id);
  }
  return pages;
}

/**
 * Fold a new outline into the one the reader is already looking at. Replanning
 * may reorder, retitle, and drop pages nobody has read, but a page that has
 * been written stays: the reader may be on it, and a link to it may exist.
 */
export function mergePages(existing, incoming, append = false) {
  if (append) {
    const known = new Set(existing.map((page) => page.id));
    for (const page of incoming)
      requireValue(!known.has(page.id), `Page already planned: ${page.id}`);
    return [...existing, ...incoming];
  }
  const written = existing.filter((page) => page.status === "written");
  const byId = new Map(existing.map((page) => [page.id, page]));
  const merged = incoming.map((page) => {
    const before = byId.get(page.id);
    return before?.status === "written"
      ? { ...before, title: page.title }
      : page;
  });
  const kept = new Set(merged.map((page) => page.id));
  return [...merged, ...written.filter((page) => !kept.has(page.id))];
}

/** The question's status is a reading of its pages, not a field the agent sets. */
export function questionStatus(question) {
  if (question.completedAt) return "done";
  if (!question.pages.length) return "asked";
  return question.pages.some((page) => page.status === "written")
    ? "writing"
    : "planned";
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
        await fetch(connection.origin + "/api/state", {
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

export async function serve(
  directory,
  { repo = process.cwd(), recover = false } = {},
) {
  const probe = createGit(repo);
  const root = (
    await probe(["rev-parse", "--show-toplevel"], { cap: 4096 }).catch(() => {
      throw new Error("Run visual-review from inside a git repository");
    })
  ).stdout
    .toString("utf8")
    .trim();
  const git = createGit(root);
  const repository = await describeRepository(git, root);

  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const release = await acquireLock(directory, recover);
  let server;
  try {
    for (const child of ["events", "questions", "repo-cache", "export"])
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
          questions: [],
          acknowledged: [],
          pending: 0,
          updatedAt: timestamp(),
        };
    requireValue(
      idPattern.test(state.sessionId) && Array.isArray(state.acknowledged),
      "Invalid session state",
    );
    state = { ...state, repo: repository };
    const transition = async (patch) => {
      state = { ...state, ...patch, updatedAt: timestamp() };
      await atomic(stateFile, state);
      return state;
    };
    await atomic(stateFile, state);

    const store = createRepository({
      root,
      git,
      cacheDir: path.join(directory, "repo-cache"),
    });

    // Every mutation runs alone, so two browser asks or an ask racing a page
    // publish cannot interleave their reads and writes of the session state.
    let serialized = Promise.resolve();
    const exclusive = (action) => {
      const result = serialized.then(action);
      serialized = result.catch(() => {});
      return result;
    };
    const eventsDir = path.join(directory, "events");
    const questionsDir = path.join(directory, "questions");

    async function allEvents() {
      const names = (await fs.readdir(eventsDir)).filter((name) =>
        name.endsWith(".json"),
      );
      const events = await Promise.all(
        names.map((name) => read(path.join(eventsDir, name))),
      );
      return events.sort((a, b) => a.sequence - b.sequence);
    }
    let sequence = (await allEvents()).reduce(
      (last, event) => Math.max(last, event.sequence),
      0,
    );
    const unread = async () =>
      (await allEvents()).filter(
        (event) => !state.acknowledged.includes(event.id),
      );

    const questionDir = (id) => path.join(questionsDir, id);
    const readQuestion = (id) =>
      read(path.join(questionDir(id), "question.json"));
    const writeQuestion = async (question) => {
      await fs.mkdir(path.join(questionDir(question.id), "pages"), {
        recursive: true,
        mode: 0o700,
      });
      await atomic(
        path.join(questionDir(question.id), "question.json"),
        question,
      );
    };

    /** Rebuild the polled state from the questions and events on disk. */
    async function refresh() {
      const ids = await fs.readdir(questionsDir).catch(() => []);
      const questions = await Promise.all(ids.map(readQuestion));
      questions.sort((a, b) => a.sequence - b.sequence);
      return transition({
        questions: questions.map((question) => ({
          id: question.id,
          title: question.title,
          text: question.text,
          status: questionStatus(question),
          statusLine: question.statusLine ?? null,
          askedAt: question.askedAt,
          context: question.context ?? null,
          followUps: question.followUps ?? [],
          pages: question.pages,
        })),
        pending: (await unread()).length,
        stage: questions.some((question) => !question.completedAt)
          ? "working"
          : "ready",
      });
    }

    async function loadQuestion(id) {
      requireValue(idPattern.test(id || ""), "A question id is required");
      const question = await readQuestion(id).catch(() => null);
      requireValue(question, `Unknown question: ${id}`, 404);
      requireValue(
        !question.completedAt,
        `Question ${id} is already done`,
        409,
      );
      return question;
    }

    /**
     * Record a browser event. An ask without a question in its context opens a
     * new question; one with a question extends the answer already being
     * written, and the agent decides where it lands.
     */
    async function ask(payload) {
      requireValue(idPattern.test(payload.id || ""), "An event id is required");
      requireValue(
        typeof payload.text === "string" && payload.text.trim(),
        "A question needs text",
      );
      requireValue(
        Buffer.byteLength(payload.text) <= 10_000,
        "Question text is too long",
        413,
      );
      const file = path.join(eventsDir, payload.id + ".json");
      if (await exists(file)) return { id: payload.id, saved: true };
      const context = payload.context ?? null;
      if (context !== null) {
        requireValue(
          typeof context === "object" && !Array.isArray(context),
          "Context must be an object",
        );
        if (context.file !== undefined) {
          context.file = normalizePath(context.file);
          context.ref = normalizeRef(context.ref ?? repository.ref);
          requireValue(
            Array.isArray(context.lines) &&
              context.lines.length === 2 &&
              context.lines.every(
                (line) => Number.isInteger(line) && line > 0,
              ) &&
              context.lines[0] <= context.lines[1],
            "Selected lines are a [start, end] pair",
          );
        }
      }
      const target = context?.questionId ?? null;
      if (target) await loadQuestion(target);
      const event = {
        id: payload.id,
        sequence: ++sequence,
        kind: "ask",
        receivedAt: timestamp(),
        payload: { ...payload, context },
      };
      await atomic(file, event);
      if (target) {
        const question = await readQuestion(target);
        question.followUps = [
          ...(question.followUps ?? []),
          {
            id: payload.id,
            text: payload.text,
            context,
            askedAt: event.receivedAt,
          },
        ];
        await writeQuestion(question);
      } else {
        await writeQuestion({
          id: payload.id,
          sequence: event.sequence,
          title: payload.text.slice(0, 80),
          text: payload.text,
          context,
          askedAt: event.receivedAt,
          statusLine: null,
          pages: [],
          followUps: [],
          completedAt: null,
        });
      }
      await refresh();
      return { id: payload.id, saved: true };
    }

    /** A picked option reaches the agent as an ask naming the block it came from. */
    async function choose(payload) {
      requireValue(
        typeof payload.option === "string" && payload.option.trim(),
        "An option is required",
      );
      requireValue(
        idPattern.test(payload.questionId || ""),
        "A question is required",
      );
      return ask({
        id: payload.id,
        text: payload.option,
        context: {
          questionId: payload.questionId,
          pageId: payload.pageId,
          blockId: payload.blockId,
        },
      });
    }

    async function act(data) {
      if (data.action === "ack") {
        requireValue(idPattern.test(data.id || ""), "An event id is required");
        if (state.acknowledged.includes(data.id)) return { state };
        const event = await read(path.join(eventsDir, data.id + ".json"));
        await transition({ acknowledged: [...state.acknowledged, event.id] });
        return { state: await refresh(), event };
      }
      if (data.action === "plan") {
        const question = await loadQuestion(data.question);
        requireValue(
          typeof data.title === "string" && data.title.trim(),
          "A plan needs a title",
        );
        question.title = data.title.trim();
        question.pages = mergePages(
          question.pages,
          parsePages(data.pages),
          data.append === true,
        );
        await writeQuestion(question);
        return { state: await refresh(), pages: question.pages };
      }
      if (data.action === "status") {
        const question = await loadQuestion(data.question);
        requireValue(
          typeof data.text === "string",
          "A status line is required",
        );
        question.statusLine = data.text.slice(0, 200) || null;
        await writeQuestion(question);
        return { state: await refresh() };
      }
      if (data.action === "page") {
        const question = await loadQuestion(data.question);
        const page = question.pages.find((entry) => entry.id === data.id);
        requireValue(
          page,
          `Page ${data.id} is not in the plan for ${question.id}; plan it first`,
        );
        requireValue(
          typeof data.markdown === "string",
          "Page Markdown is required",
        );
        requireValue(
          Buffer.byteLength(data.markdown) <= 1024 * 1024,
          "A page is limited to 1 MB",
          413,
        );
        await fs.writeFile(
          path.join(questionDir(question.id), "pages", page.id + ".md"),
          data.markdown,
          { mode: 0o600 },
        );
        page.status = "written";
        page.revision = (page.revision ?? 0) + 1;
        page.updatedAt = timestamp();
        await writeQuestion(question);
        return { state: await refresh(), page };
      }
      if (data.action === "done") {
        const question = await loadQuestion(data.question);
        question.pages = question.pages.filter(
          (page) => page.status === "written",
        );
        question.completedAt = timestamp();
        question.statusLine = null;
        await writeQuestion(question);
        return { state: await refresh(), pages: question.pages };
      }
      requireValue(false, `Unknown agent action: ${data.action}`);
    }

    async function pageMarkdown(questionId, pageId) {
      requireValue(idPattern.test(questionId || ""), "A question is required");
      requireValue(pageIdPattern.test(pageId || ""), "A page is required");
      return fs.readFile(
        path.join(questionDir(questionId), "pages", pageId + ".md"),
        "utf8",
      );
    }

    await refresh();
    const token = crypto.randomBytes(32).toString("hex");
    let origin;

    const shell = await fs.readFile(path.join(assets, "app.html"), "utf8");

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
        const query = url.searchParams;
        if (req.method === "GET" && url.pathname === "/")
          return reply(
            200,
            shell.replace(
              /(<script\b(?=[^>]*\bid=["']session-config["'])[^>]*>)[\s\S]*?(<\/script>)/i,
              (_, start, end) =>
                start +
                json({
                  sessionId: state.sessionId,
                  repo: repository,
                }).replaceAll("<", "\\u003c") +
                end,
            ),
            "text/html; charset=utf-8",
          );
        if (req.method === "GET" && url.pathname === "/api/state")
          return reply(200, state);
        if (req.method === "GET" && url.pathname.startsWith("/assets/")) {
          const name = url.pathname.slice(8);
          requireValue(
            /^[a-z0-9][a-z0-9.-]{0,63}$/.test(name),
            "Not found",
            404,
          );
          const types = {
            ".css": "text/css; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".mjs": "text/javascript; charset=utf-8",
          };
          return reply(
            200,
            await fs.readFile(path.join(assets, name)),
            types[path.extname(name)] || "application/octet-stream",
          );
        }
        if (req.method === "GET" && url.pathname === "/api/page")
          return reply(
            200,
            await pageMarkdown(query.get("question"), query.get("id")),
            "text/markdown; charset=utf-8",
          );
        if (req.method === "GET" && url.pathname === "/agent/next") {
          requireValue(
            req.headers.authorization === `Bearer ${token}`,
            "Agent token required",
            403,
          );
          return reply(
            200,
            await exclusive(async () => ({
              state,
              event: (await unread())[0] || null,
            })),
          );
        }
        if (req.method === "POST") {
          const agent = url.pathname === "/agent/action";
          requireValue(
            agent || ["/api/ask", "/api/choose"].includes(url.pathname),
            "Not found",
            404,
          );
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
              Buffer.byteLength(raw) <= (agent ? 4_000_000 : 250_000),
              "Request too large",
              413,
            );
          }
          const data = JSON.parse(raw);
          requireValue(
            data.sessionId === state.sessionId,
            "Wrong session",
            409,
          );
          return reply(
            200,
            await exclusive(() =>
              agent
                ? act(data)
                : url.pathname === "/api/ask"
                  ? ask(data)
                  : choose(data),
            ),
          );
        }
        if (req.method === "GET" && url.pathname === "/repo/file")
          return reply(
            200,
            await store.file(
              query.get("path"),
              query.get("ref") || repository.ref,
            ),
          );
        if (req.method === "GET" && url.pathname === "/repo/tree")
          return reply(
            200,
            await store.tree(
              query.get("path") || "",
              query.get("ref") || repository.ref,
            ),
          );
        if (req.method === "GET" && url.pathname === "/repo/paths")
          return reply(
            200,
            await store.paths(
              query.get("ref") || repository.ref,
              query.get("q") || "",
              query.get("limit"),
            ),
          );
        if (req.method === "GET" && url.pathname === "/repo/exists")
          return reply(
            200,
            await store.entry(
              query.get("path"),
              query.get("ref") || repository.ref,
            ),
          );
        if (req.method === "GET" && url.pathname === "/repo/diff") {
          requireValue(
            query.get("base") && query.get("head"),
            "base and head are required",
          );
          return reply(
            200,
            await store.diff(
              query.get("base"),
              query.get("head"),
              query.get("path") ?? undefined,
            ),
          );
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
        url: origin + "/",
        repo: repository,
      }),
    );
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      await new Promise((resolve) => server.close(resolve));
      await release();
    };
    return {
      close,
      origin,
      sessionId: state.sessionId,
      repo: repository,
      store,
    };
  } catch (error) {
    server?.close();
    await release();
    throw error;
  }
}

const flags = new Set(["recover-lock", "append"]);

function argumentsFrom(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let i = 0; i < rest.length; i++) {
    requireValue(rest[i].startsWith("--"), "Options must use --name value");
    const key = rest[i].slice(2);
    if (flags.has(key)) options[key] = true;
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
      "visual-review",
      "sessions",
      crypto.randomUUID(),
    );
    const session = await serve(directory, {
      repo: options.repo ? path.resolve(options.repo) : process.cwd(),
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
      signal: AbortSignal.timeout(60_000),
    });
    const result = await response.json();
    requireValue(
      response.ok,
      result.error || "Request failed",
      response.status,
    );
    requireValue(
      (result.state?.sessionId || result.sessionId) === connection.sessionId,
      "Helper identity changed; resume the intended session",
      409,
    );
    return result;
  }

  if (command === "state") {
    const response = await fetch(connection.origin + "/api/state", {
      signal: AbortSignal.timeout(15_000),
    });
    return console.log(json(await response.json()));
  }
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
  if (["plan", "status", "page", "done"].includes(command))
    action.question = options.question;
  if (command === "plan") {
    action.title = options.title;
    action.pages = options.pages;
    action.append = options.append === true;
  }
  if (command === "status") action.text = options.text ?? "";
  if (command === "page") {
    requireValue(options.id, "page requires --id PID");
    requireValue(options.file, "page requires --file PATH");
    action.id = options.id;
    action.markdown = await fs.readFile(path.resolve(options.file), "utf8");
  }
  requireValue(
    ["ack", "plan", "status", "page", "done"].includes(command),
    `Unknown command: ${command}`,
  );
  console.log(json(await request("/agent/action", action)));
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`visual-review: ${error.message}`);
    process.exitCode = 1;
  });
}
