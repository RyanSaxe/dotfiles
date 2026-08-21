// Renders the Worktrees subtab through the real renderer.
//
//   npx tsx scripts/worktreeframe.ts | uv run -q --script scripts/ansi2png.py out.png

import { renderDashboard } from "../src/dashboard.js";
import { worktreeDashboardData } from "../src/review-dashboard.js";
import { loadPalette } from "../src/theme.js";

process.stdout.write(
  renderDashboard(
    await worktreeDashboardData(),
    Number(process.env["FRAME_SELECTED"] ?? "0"),
    loadPalette(),
    110,
    24,
    "",
    false,
    0,
    "worktrees",
  ),
);
