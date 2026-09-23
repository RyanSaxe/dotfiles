#!/usr/bin/env node
import path from "node:path";
import { pathToFileURL } from "node:url";

const argument = (name) => {
  const index = process.argv.indexOf(name);
  return index < 0 ? null : process.argv[index + 1];
};

const file = argument("--file");
const pageId = argument("--page-id");
if (!file || !pageId) {
  console.error("Usage: node render-check.mjs --file HTML --page-id ID");
  process.exit(2);
}

let playwright;
try {
  playwright = await import("playwright");
} catch {
  console.error("The pinned Playwright runner is unavailable.");
  process.exit(2);
}

let browser;
try {
  browser = await playwright.chromium.launch({ headless: true });
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(
    `${pathToFileURL(path.resolve(file)).href}#${encodeURIComponent(pageId)}`,
    {
      waitUntil: "load",
    },
  );
  await page.waitForFunction(
    () => document.documentElement.dataset.planReady === "true",
    null,
    { timeout: 15_000 },
  );
  const result = await page.evaluate(
    (id) => ({
      title: document.querySelector("#page-title")?.textContent?.trim(),
      content: document.querySelector("#page-content")?.textContent?.trim(),
      pending: document.querySelector(
        `[data-workset-pending][data-page-id="${CSS.escape(id)}"]`,
      ),
      renderErrors: [...document.querySelectorAll(".renderer-error")].map(
        (item) => item.textContent,
      ),
    }),
    pageId,
  );
  if (
    !result.title ||
    !result.content ||
    result.pending ||
    result.renderErrors.length ||
    errors.length
  )
    throw new Error(
      [
        ...errors,
        ...result.renderErrors,
        "Required page content was not ready",
      ].join("; "),
    );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await browser?.close();
}
