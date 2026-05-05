#!/usr/bin/env node
// screenshot.js — playwright self-review harness for visual artifacts.
//
// Used by skill-builder during Phase 2 (calibrate via samples) so the
// agent can iterate on a rendered artifact via screenshots before
// showing the user.
//
// Usage:
//   node tools/screenshot.js <html-file> [<html-file> ...]
//
// Each HTML file is opened in headless chromium at three viewports
// (16:9 desktop, wide desktop, portrait tablet). Screenshots land in
// /tmp/skill-screenshots/<viewport>/<basename>/.
//
// Reveal-detection: if the page exposes window.Reveal, every slide is
// screenshotted (with all fragments revealed). Otherwise a single
// full-page screenshot is taken.
//
// Requires playwright. If you don't have it installed:
//   npm install -g playwright && npx playwright install chromium

const path = require('path');
const fs = require('fs');

// Find playwright in: the script's tree, the cwd, or the first arg's directory.
// Iterating samples often happens in /tmp/<sample>/ where the user has run
// `npm install playwright` locally.
function findPlaywright() {
  const tries = [
    () => require('playwright'),
    () => require(path.join(process.cwd(), 'node_modules', 'playwright')),
  ];
  if (process.argv[2]) {
    tries.push(() => require(path.join(path.dirname(path.resolve(process.argv[2])), 'node_modules', 'playwright')));
  }
  for (const t of tries) {
    try { return t(); } catch {}
  }
  return null;
}

const pw = findPlaywright();
if (!pw) {
  console.error('playwright not installed. Install it in one of:');
  console.error('  - globally: npm install -g playwright && npx playwright install chromium');
  console.error('  - in your sample dir: cd <dir> && npm install playwright && npx playwright install chromium');
  process.exit(2);
}
const { chromium } = pw;

const VIEWPORTS = [
  { name: '16x9',     width: 1280, height: 800  },
  { name: 'wide',     width: 1920, height: 1080 },
  { name: 'portrait', width: 900,  height: 1200 },
];

const SHOTS_DIR = '/tmp/skill-screenshots';

async function shootDeck(page, dir) {
  await page.waitForFunction(() => window.Reveal && window.Reveal.isReady && window.Reveal.isReady());
  await page.waitForTimeout(400);

  const total = await page.evaluate(() => window.Reveal.getTotalSlides());

  for (let i = 0; i < total; i++) {
    await page.evaluate((idx) => window.Reveal.slide(idx), i);
    await page.evaluate(() => {
      // Reveal all fragments so the screenshot shows the slide complete
      document.querySelectorAll('.present .fragment').forEach(f => {
        f.classList.add('visible', 'current-fragment');
      });
    });
    await page.waitForTimeout(700); // chart/math render time
    const num = String(i + 1).padStart(2, '0');
    await page.screenshot({ path: path.join(dir, `slide-${num}.png`), fullPage: false });
  }
  return total;
}

async function shootPage(page, dir) {
  await page.waitForTimeout(700);
  await page.screenshot({ path: path.join(dir, 'page.png'), fullPage: true });
  return 1;
}

async function shoot(file, viewport) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const page = await ctx.newPage();

  const fileUrl = 'file://' + path.resolve(file);
  await page.goto(fileUrl, { waitUntil: 'networkidle' });

  const isDeck = await page.evaluate(() => typeof window.Reveal !== 'undefined');

  // Use parent folder name when the file is generically named (e.g. index.html).
  const stem = path.basename(file, path.extname(file));
  const base = stem === 'index' ? path.basename(path.dirname(path.resolve(file))) : stem;
  const dir = path.join(SHOTS_DIR, viewport.name, base);
  fs.mkdirSync(dir, { recursive: true });

  const n = isDeck ? await shootDeck(page, dir) : await shootPage(page, dir);

  await browser.close();
  return { n, isDeck, dir };
}

(async () => {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('Usage: node screenshot.js <html-file> [<html-file> ...]');
    process.exit(2);
  }

  // Clean shots dir
  if (fs.existsSync(SHOTS_DIR)) fs.rmSync(SHOTS_DIR, { recursive: true });

  for (const file of files) {
    if (!fs.existsSync(file)) {
      console.error(`skip: ${file} not found`);
      continue;
    }
    for (const vp of VIEWPORTS) {
      const { n, isDeck, dir } = await shoot(file, vp);
      const kind = isDeck ? `${n} slides` : 'full page';
      console.log(`${path.basename(file)} ${vp.name}: ${kind} → ${dir}/`);
    }
  }
})();
