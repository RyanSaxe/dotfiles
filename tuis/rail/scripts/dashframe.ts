// Renders one dashboard frame through the real renderer, for the look loop.
// Pipe it through ansi2png.py to judge cells by eye rather than by unit test.
//
//   npx tsx scripts/dashframe.ts "ret val" | uv run -q --script scripts/ansi2png.py out.png
//   npx tsx scripts/dashframe.ts --demo    | uv run -q --script scripts/ansi2png.py out.png
//
// --demo renders a mixed inbox: a live one is usually all of a kind, which
// hides whether the CI/pull-request/issue hues actually read apart.

import {
  renderDashboard,
  type DashboardData,
  type DashboardItem,
} from "../src/dashboard.js";
import { reviewDashboardData } from "../src/review-dashboard.js";
import { loadPalette } from "../src/theme.js";

const demo = (
  repository: string,
  reference: string,
  from: string,
  author: string,
  authorIsViewer: boolean,
  reason: string,
  time: string,
  tone: DashboardItem["tone"],
  preview: DashboardItem["preview"],
): DashboardItem => ({
  id: `${repository}${reference}`,
  repository,
  reference,
  from,
  author,
  authorIsViewer,
  reason,
  time,
  title: preview.context[0] ?? "",
  url: null,
  tone,
  preview,
});

const DEMO: DashboardData = {
  surface: "reviews",
  status: "6 need you",
  emptyMessage: "Review inbox is clear",
  error: null,
  items: [
    demo(
      "RyanSaxe/buffergolf.nvim",
      "#4",
      "—",
      "@RyanSaxe",
      true,
      "CI failed",
      "290d",
      "ci",
      {
        headline: "CI failed on buffergolf.nvim#4",
        bullets: ["lint", "typecheck"],
        body: [],
        context: ["Test PR 2: Add return value documentation"],
      },
    ),
    demo(
      "RyanSaxe/buffergolf.nvim",
      "#6",
      "—",
      "@alice",
      false,
      "Review requested",
      "1d",
      "pull_request",
      {
        headline: "Review requested on buffergolf.nvim#6",
        bullets: [],
        body: ["Clarifies when the plugin disables itself during a session."],
        context: ["Clarify plugin disabling timing", "opened by @alice"],
      },
    ),
    demo(
      "RyanSaxe/dotfiles-v2",
      "#94",
      "@alice",
      "@RyanSaxe",
      true,
      "Commented on your PR",
      "2h",
      "pull_request",
      {
        headline: "@alice commented on dotfiles-v2#94",
        bullets: [],
        body: [
          "The resolver should probably clone into ~/repositories rather than reusing ~/generic — otherwise `to` picks up review checkouts as if they were projects.",
        ],
        context: ["feat(rail): add review workspaces"],
      },
    ),
    demo(
      "RyanSaxe/dotfiles-v2",
      "#312",
      "@bob",
      "@RyanSaxe",
      true,
      "Commented on your issue",
      "3d",
      "issue",
      {
        headline: "@bob commented on dotfiles-v2#312",
        bullets: [],
        body: [
          "Still flickers on mocha to latte, but only on the second switch.",
        ],
        context: ["Rail flickers on theme switch"],
      },
    ),
    demo(
      "someorg/infra",
      "#77",
      "@dana",
      "@dana",
      false,
      "New PR opened",
      "12m",
      "pull_request",
      {
        headline: "@dana opened someorg/infra#77",
        bullets: [],
        body: ["Rotates the staging credentials and drops the unused role."],
        context: ["Rotate staging credentials", "opened by @dana"],
      },
    ),
    demo(
      "someorg/infra",
      "#481",
      "@erin",
      "@erin",
      false,
      "New issue opened",
      "40m",
      "issue",
      {
        headline: "@erin opened someorg/infra#481",
        bullets: [],
        body: ["Deploys intermittently fail to pick up the new secret."],
        context: ["Deploy misses rotated secret", "opened by @erin"],
      },
    ),
  ],
};

const args = process.argv.slice(2);
const isDemo = args.includes("--demo");
const query = args.find((value) => !value.startsWith("--")) ?? "";
const selected = Number(process.env["FRAME_SELECTED"] ?? "0");
const offset = Number(process.env["FRAME_OFFSET"] ?? "0");

process.stdout.write(
  renderDashboard(
    isDemo ? DEMO : reviewDashboardData(),
    selected,
    loadPalette(),
    110,
    24,
    query,
    query !== "",
    offset,
  ),
);
