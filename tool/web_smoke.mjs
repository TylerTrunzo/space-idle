// Web smoke test for the Space Idle release build.
//
// Serve the build first:
//   (cd app && flutter build web --release --no-web-resources-cdn)
//   python3 -m http.server 8080 --directory app/build/web
// then run, with Playwright installed globally:
//   NODE_PATH="$(npm root -g)" node tool/web_smoke.mjs [--url http://127.0.0.1:8080/]
//        [--save packages/game_core/test/fixtures/balanced_s1_d14.json]
//        [--out docs/screenshots] [--seconds 10]
//
// At 412×915 (a phone) it waits for the app, turns semantics on, and checks
// the star map shows Kora, then:
// - screenshots the map, Kora's panel and the Projects tab;
// - loads a late save through the settings sheet (Load save, confirm) and
//   measures frame times on the map for --seconds;
// - screenshots the late game.
// At 1280×800 it screenshots the map and the side panel.
//
// It fails (exit code 1) if Kora isn't on the map within 20 s, if a step
// can't find what it taps, or if the page logs a console error or throws.
// Screenshots use deviceScaleFactor 2. The frame figures are printed as
// JSON at the end.

import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  console.error(
    'Playwright not found: run with NODE_PATH="$(npm root -g)" or npm i playwright',
  );
  process.exit(2);
}

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const url = arg('url', 'http://127.0.0.1:8080/');
const out = arg('out', 'docs/screenshots');
const savePath = arg(
  'save',
  'packages/game_core/test/fixtures/balanced_s1_d14.json',
);
const seconds = Number(arg('seconds', '10'));
mkdirSync(out, { recursive: true });

/// Every console error and uncaught exception the pages report.
const problems = [];

/// Semantics nodes are <flt-semantics> elements; buttons carry their label
/// as text, tabs as aria-label.
const button = (page, text) =>
  page.locator('flt-semantics[role="button"]', { hasText: text }).first();
const tab = (page, label) =>
  page.locator(`flt-semantics[role="tab"][aria-label="${label}"]`).first();

async function open(browser, width, height) {
  const context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`uncaught: ${e.message}`));
  await page.goto(url);
  // Flutter puts a placeholder in the page that turns semantics on when
  // clicked; it sits off screen, so click it from the page itself.
  await page.waitForSelector('flt-semantics-placeholder', {
    state: 'attached',
    timeout: 30000,
  });
  await page.evaluate(() =>
    document.querySelector('flt-semantics-placeholder').click(),
  );
  try {
    await button(page, 'Kora, owned').waitFor({ timeout: 20000 });
  } catch {
    throw new Error('Kora is not on the star map after 20 s');
  }
  return { context, page };
}

async function shot(page, name) {
  // The pointer off the controls, so no hover tooltip shows; then time for
  // the last tap to land on screen.
  await page.mouse.move(1, 1);
  await page.waitForTimeout(1200);
  const path = join(out, name);
  await page.screenshot({ path });
  console.log(`screenshot ${path}`);
}

/// Frame intervals over [secs] seconds, from requestAnimationFrame: what the
/// player sees, the game's 1 s ticks and their frames included. Beside them,
/// Chrome's own counters for the same span: the main thread's time in script
/// (the app's Dart, compiled to JS) and in all tasks, a share of the span.
async function frames(page, secs) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable');
  const metric = async () => {
    const { metrics } = await cdp.send('Performance.getMetrics');
    return Object.fromEntries(metrics.map((m) => [m.name, m.value]));
  };
  const before = await metric();
  const gaps = await page.evaluate(
    (ms) =>
      new Promise((resolve) => {
        const gaps = [];
        const start = performance.now();
        let last = start;
        const step = (t) => {
          gaps.push(t - last);
          last = t;
          if (t - start < ms) requestAnimationFrame(step);
          else resolve(gaps);
        };
        requestAnimationFrame(step);
      }),
    secs * 1000,
  );
  const after = await metric();
  const sorted = [...gaps].sort((a, b) => a - b);
  const at = (q) => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
  const total = gaps.reduce((t, g) => t + g, 0);
  const round = (v) => Math.round(v * 10) / 10;
  return {
    seconds: round(total / 1000),
    frames: gaps.length,
    fps: round(gaps.length / (total / 1000)),
    medianMs: round(at(0.5)),
    p95Ms: round(at(0.95)),
    maxMs: round(sorted[sorted.length - 1]),
    over25Ms: gaps.filter((g) => g > 25).length,
    scriptShare: round(
      ((after.ScriptDuration - before.ScriptDuration) / (total / 1000)) * 100,
    ),
    taskShare: round(
      ((after.TaskDuration - before.TaskDuration) / (total / 1000)) * 100,
    ),
  };
}

async function loadSave(page, text) {
  await button(page, 'Settings').click();
  const field = page
    .locator('flt-semantics input, flt-semantics textarea, textarea, input')
    .first();
  await page.waitForTimeout(800);
  // The paste field: tapping it gives Flutter's editing element the focus.
  const label = page.getByText('Paste a save to load').first();
  await (await label.count() ? label : field).click();
  await page.waitForTimeout(500);
  await page.keyboard.insertText(text);
  await page.waitForTimeout(500);
  await button(page, 'Load save').click();
  await page.waitForTimeout(500);
  await button(page, /^Load$/).click();
  await page.getByText('Save loaded').first().waitFor({ timeout: 20000 });
}

const browser = await chromium.launch();
const timing = {};
try {
  // A phone.
  {
    const { context, page } = await open(browser, 412, 915);
    await shot(page, 'web-phone.png');
    timing.newGame = await frames(page, seconds);

    await button(page, 'Kora, owned').click();
    await shot(page, 'web-phone-panel.png');

    await tab(page, 'Projects').click();
    await shot(page, 'web-phone-projects.png');

    await tab(page, 'Map').click();
    await loadSave(page, readFileSync(savePath, 'utf8'));
    // Let the fills settle (previews, the best upgrade, the income).
    await page.waitForTimeout(4000);
    await shot(page, 'web-phone-late.png');
    timing.lateSave = { save: savePath, ...(await frames(page, seconds)) };
    // The same game on a tab with no animation: what the ticks cost alone.
    await tab(page, 'Trade').click();
    await page.waitForTimeout(1500);
    timing.lateSaveTradeTab = await frames(page, seconds);
    await context.close();
  }
  // A laptop.
  {
    const { context, page } = await open(browser, 1280, 800);
    await shot(page, 'web-wide.png');
    await button(page, 'Kora, owned').click();
    await shot(page, 'web-wide-panel.png');
    await context.close();
  }
} catch (e) {
  problems.push(`step failed: ${e.message}`);
} finally {
  await browser.close();
}

console.log(JSON.stringify({ timing }, null, 2));
if (problems.length > 0) {
  console.error(`FAILED: ${problems.length} problem(s)`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log('OK');
