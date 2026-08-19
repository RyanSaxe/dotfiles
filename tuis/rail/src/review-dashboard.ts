import { spawn } from "node:child_process";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { resolve } from "node:path";

import { main as attentionMain } from "./attention/cli.js";
import { loadReviewSnapshot } from "./attention/review.js";
import {
  acknowledgeItem,
  loadObserverState,
  saveObserverState,
} from "./attention/state.js";
import type { AttentionItem } from "./attention/types.js";

const run = promisify(execFile);

interface DashboardChoice {
  action: "open" | "ack" | "refresh";
  itemIndex: number;
}

function clean(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function repositoryLabel(item: AttentionItem): string {
  const slash = item.repository.lastIndexOf("/");
  const repository =
    slash >= 0 ? item.repository.slice(slash + 1) : item.repository;
  return `${repository}#${item.number}`;
}

export function formatReviewRow(
  index: number,
  item: AttentionItem,
  acknowledged: boolean,
): string {
  const marker = acknowledged ? "✓" : "•";
  const actor = item.actor?.login ?? "GitHub";
  return [
    String(index + 1).padStart(2),
    `${marker} ${repositoryLabel(item)}`,
    actor,
    clean(item.title),
    "—",
    clean(item.summary),
  ].join("\t");
}

export function parseFzfOutput(output: string): DashboardChoice | null {
  const lines = output.replace(/\r/g, "").split("\n");
  while (lines.at(-1) === "") lines.pop();
  const selected = lines.at(-1);
  if (selected === undefined || selected === "") return null;
  const itemIndex = Number.parseInt(selected.split("\t", 1)[0] ?? "", 10) - 1;
  if (!Number.isInteger(itemIndex) || itemIndex < 0) return null;

  const key = lines.length > 1 ? lines[0] : "";
  switch (key) {
    case "ctrl-d":
      return { action: "ack", itemIndex };
    case "ctrl-r":
      return { action: "refresh", itemIndex };
    default:
      return { action: "open", itemIndex };
  }
}

function choose(
  items: AttentionItem[],
  acknowledged: ReadonlySet<string>,
): Promise<DashboardChoice | null> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "fzf",
      [
        "--ansi",
        "--border=rounded",
        "--expect=ctrl-d,ctrl-r",
        "--header=Enter open in browser  •  ctrl-d acknowledge  •  ctrl-r refresh  •  Esc close",
        "--height=100%",
        "--layout=reverse",
        "--no-multi",
        "--nth=2..",
        "--pointer=▌",
        "--prompt=Review > ",
      ],
      { stdio: ["pipe", "pipe", "inherit"] },
    );
    let output = "";
    child.stdout?.setEncoding("utf8");
    child.stdout?.on("data", (chunk: string) => {
      output += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        resolve(null);
        return;
      }
      resolve(parseFzfOutput(output));
    });
    child.stdin?.end(
      items
        .map((item, index) =>
          formatReviewRow(index, item, acknowledged.has(item.id)),
        )
        .join("\n"),
    );
  });
}

async function acknowledge(id: string): Promise<void> {
  const state = await loadObserverState();
  await saveObserverState(acknowledgeItem(state, id));
}

async function openUrl(url: string): Promise<void> {
  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  await run(opener, [url]);
}

export async function main(): Promise<void> {
  for (;;) {
    const snapshot = loadReviewSnapshot();
    if (snapshot.items.length === 0) {
      console.log("Review inbox is clear.");
      return;
    }
    const choice = await choose(snapshot.items, snapshot.acknowledged);
    if (choice === null) return;
    const item = snapshot.items[choice.itemIndex];
    if (item === undefined) continue;

    if (choice.action === "ack") {
      await acknowledge(item.id);
      continue;
    }
    if (choice.action === "refresh") {
      await attentionMain(["refresh", "--no-notify"]);
      continue;
    }
    await openUrl(item.url);
    return;
  }
}

const thisFile = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === thisFile) {
  main().catch((error: unknown) => {
    console.error(
      `review dashboard: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exitCode = 1;
  });
}
