// Renders one dashboard frame through the real renderer, for the look loop.
// Pipe it through ansi2png.py to judge cells by eye rather than by unit test.
//
//   npx tsx scripts/dashframe.ts "ret val" | uv run -q --script scripts/ansi2png.py out.png

import { renderDashboard } from "../src/dashboard.js";
import { reviewDashboardData } from "../src/review-dashboard.js";
import { loadPalette } from "../src/theme.js";

const query = process.argv[2] ?? "";
process.stdout.write(
  renderDashboard(
    reviewDashboardData(),
    0,
    loadPalette(),
    110,
    22,
    query,
    query !== "",
  ),
);
