import { execFile, spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

// A test must build its own repository even when it runs inside a git hook,
// which exports GIT_DIR and friends pointing at the repository being committed.
const environment = Object.fromEntries(
  Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")),
);

/** Run git against a fixture repository, ignoring any ambient git environment. */
export async function inspect(cwd, args) {
  const { stdout } = await run("git", args, { cwd, env: environment });
  return stdout.trim();
}

export async function temporaryDirectory(name) {
  return fs.mkdtemp(path.join(os.tmpdir(), `visual-review-${name}-`));
}

async function git(cwd, args) {
  return run("git", args, {
    cwd,
    env: environment,
    maxBuffer: 64 * 1024 * 1024,
  });
}

async function initialize(root) {
  await git(root, ["init", "--quiet", "--initial-branch=main"]);
  await git(root, ["config", "user.email", "tests@example.invalid"]);
  await git(root, ["config", "user.name", "Visual Review Tests"]);
  await git(root, ["config", "commit.gpgsign", "false"]);
  // A fixture repository never wants the machine's hooks.
  await git(root, [
    "config",
    "core.hooksPath",
    path.join(root, ".git/no-hooks"),
  ]);
}

/**
 * A small repository with two commits, a binary blob, a file past the 2 MB
 * ceiling, and a bare origin carrying refs/pull/7/head.
 */
export async function createSampleRepository() {
  const root = await temporaryDirectory("repo");
  await initialize(root);
  const write = async (file, contents) => {
    await fs.mkdir(path.join(root, path.dirname(file)), { recursive: true });
    await fs.writeFile(path.join(root, file), contents);
  };
  await write("README.md", "# Sample\n");
  await write("src/client.py", "class Client:\n    ATTEMPTS = 5\n");
  await write("src/gateway.py", "def post(path):\n    return path\n");
  await write("src/ledger/writer.py", "def append(entry):\n    return entry\n");
  await write("assets/logo.bin", Buffer.from([0x89, 0x50, 0x00, 0x01, 0x02]));
  await write("big.txt", "x".repeat(3 * 1024 * 1024) + "\n");
  await git(root, ["add", "-A"]);
  await git(root, ["commit", "--quiet", "-m", "first"]);
  const first = (await git(root, ["rev-parse", "HEAD"])).stdout.trim();

  await write(
    "src/client.py",
    "class Client:\n    ATTEMPTS = 5\n    BREAKER = True\n",
  );
  await git(root, ["add", "-A"]);
  await git(root, ["commit", "--quiet", "-m", "second"]);
  const second = (await git(root, ["rev-parse", "HEAD"])).stdout.trim();

  // A pull request head lives in a bare origin, exactly as GitHub serves it.
  const origin = await temporaryDirectory("origin");
  await git(origin, ["init", "--quiet", "--bare"]);
  await git(root, ["remote", "add", "origin", origin]);
  await git(root, ["push", "--quiet", "origin", "main"]);
  await write(
    "src/client.py",
    "class Client:\n    ATTEMPTS = 7\n    BREAKER = True\n",
  );
  await git(root, ["add", "-A"]);
  await git(root, ["commit", "--quiet", "-m", "pull request"]);
  const pull = (await git(root, ["rev-parse", "HEAD"])).stdout.trim();
  await git(root, ["push", "--quiet", "origin", "HEAD:refs/pull/7/head"]);
  await git(root, ["reset", "--hard", "--quiet", second]);

  return { root, origin, first, second, pull };
}

/**
 * A repository whose committed tree holds `files` blobs spread over
 * `directories` directories, built through fast-import so no working tree is
 * written, plus an ignored directory that exists only on disk.
 */
export async function createLargeRepository({
  files = 100_000,
  directories = 1000,
  ignored = 300,
} = {}) {
  const root = await temporaryDirectory("large");
  await initialize(root);
  const stream = [];
  stream.push("blob\nmark :1\ndata 6\nhello\n\n");
  stream.push("blob\nmark :2\ndata 7\n.venv/\n\n");
  stream.push(
    "commit refs/heads/main\nmark :3\n" +
      "author Tests <tests@example.invalid> 0 +0000\n" +
      "committer Tests <tests@example.invalid> 0 +0000\n" +
      "data 4\nbulk\n",
  );
  stream.push("M 100644 :2 .gitignore\n");
  const perDirectory = Math.ceil(files / directories);
  for (let index = 0; index < files; index += 1) {
    const directory = Math.floor(index / perDirectory);
    stream.push(
      `M 100644 :1 pkg/dir${String(directory).padStart(4, "0")}/file${String(index).padStart(6, "0")}.txt\n`,
    );
  }
  stream.push("\ndone\n");
  await new Promise((resolve, reject) => {
    const child = spawn("git", ["fast-import", "--quiet", "--done"], {
      cwd: root,
      env: environment,
      stdio: ["pipe", "ignore", "pipe"],
    });
    const errors = [];
    child.stderr.on("data", (chunk) => errors.push(chunk));
    child.on("error", reject);
    child.on("close", (code) =>
      code === 0
        ? resolve()
        : reject(new Error(Buffer.concat(errors).toString("utf8"))),
    );
    child.stdin.end(stream.join(""));
  });
  // Untracked, ignored working-tree files the helper must never surface.
  await fs.mkdir(path.join(root, ".venv/lib"), { recursive: true });
  await Promise.all(
    Array.from({ length: ignored }, (_, index) =>
      fs.writeFile(path.join(root, `.venv/lib/module${index}.py`), "secret\n"),
    ),
  );
  return { root, files };
}

export async function removeAll(...roots) {
  await Promise.all(
    roots
      .filter(Boolean)
      .map((root) => fs.rm(root, { recursive: true, force: true })),
  );
}
