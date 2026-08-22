// Renders the diff view through the real renderer, for the look loop.
//
//   npx tsx scripts/diffframe.ts RyanSaxe/buffergolf.nvim 7 \
//     | uv run -q --script scripts/ansi2png.py out.png

import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { renderDiffView } from "../src/dashboard.js";
import { loadPalette } from "../src/theme.js";

const run = promisify(execFile);
const repository = process.argv[2] ?? "RyanSaxe/buffergolf.nvim";
const number = process.argv[3] ?? "7";
const offset = Number(process.env["FRAME_OFFSET"] ?? "0");

const { stdout } = await run(
  "sh",
  [
    "-c",
    'gh pr diff "$1" --repo "$2" | delta --paging=never --width "$3"',
    "sh",
    number,
    repository,
    "108",
  ],
  { maxBuffer: 32 * 1024 * 1024 },
);

process.stdout.write(
  renderDiffView(
    `${repository}#${number}`,
    stdout.replace(/\n$/, "").split("\n"),
    offset,
    loadPalette(),
    110,
    26,
  ),
);
