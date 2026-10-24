#!/usr/bin/env node
// Start a compiled Flutter web preview, then run:
//   node tool/visual_smoke.cjs
// Resolve Playwright through the project's Node environment or NODE_PATH.
// Optional: RECALL_BASE_URL, RECALL_SCREENSHOTS_DIR, PLAYWRIGHT_CHANNEL.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const baseUrl = process.env.RECALL_BASE_URL || 'http://127.0.0.1:8766';
const output = path.resolve(process.env.RECALL_SCREENSHOTS_DIR || 'artifacts');
const captures = [];
const errors = [];
let browser;

async function settle(page) {
  // Flutter route animations and tooltip dismissal must finish before capture.
  await page.mouse.move(1, 1);
  await page.waitForTimeout(1400);
}

async function capture(page, name) {
  await settle(page);
  const file = `${name}.png`;
  await page.screenshot({ path: path.join(output, file) });
  captures.push({ file, viewport: page.viewportSize() });
  fs.writeFileSync(
    path.join(output, `${name}-semantics.txt`),
    await page.locator('body').innerText(),
  );
}

async function goBack(page) {
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await settle(page);
}

async function main() {
  fs.mkdirSync(output, { recursive: true });
  browser = await chromium.launch({
    channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome',
    headless: true,
  });
  // A fresh, ephemeral context keeps this journey away from a user's workspace.
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    colorScheme: 'light',
  });
  const page = await context.newPage();
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  const semantics = page.locator('flt-semantics-placeholder');
  await semantics.waitFor({ state: 'attached', timeout: 60000 });
  await semantics.evaluate((element) => element.click());
  await capture(page, 'review-mobile-welcome');
  await page.getByRole('button', { name: 'Explore the example', exact: true }).click();
  await capture(page, 'review-mobile-today');
  await page.getByRole('tab', { name: 'Projects', exact: true }).click();
  await capture(page, 'review-mobile-projects');
  await page.getByRole('button', { name: /Launch films/ }).first().click();
  await capture(page, 'review-mobile-project');
  await page.getByRole('button', { name: 'Add update', exact: true }).last().click();
  await capture(page, 'review-mobile-update-editor');
  await goBack(page);
  await goBack(page);
  await page.getByRole('tab', { name: 'Today', exact: true }).click();
  await settle(page);
  await page.getByRole('button', { name: /^Launch films/ }).first().click();
  await capture(page, 'review-mobile-revision');
  await goBack(page);
  await page.getByRole('button', { name: 'Your workspace', exact: true }).click();
  await capture(page, 'review-mobile-settings');
  await page.emulateMedia({ colorScheme: 'dark' });
  await capture(page, 'review-mobile-settings-dark');
  await page.emulateMedia({ colorScheme: 'light' });
  await goBack(page);
  await page.setViewportSize({ width: 1365, height: 1000 });
  await capture(page, 'review-desktop-today');
  await page.getByRole('button', { name: /^Launch films/ }).first().click();
  await capture(page, 'review-desktop-revision');
  fs.writeFileSync(
    path.join(output, 'visual-smoke.json'),
    JSON.stringify({ baseUrl, capturedAt: new Date().toISOString(), captures, errors }, null, 2),
  );
  console.log(JSON.stringify({ output, screenshots: captures.length, errors }, null, 2));
  if (errors.length) process.exitCode = 1;
}

main()
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    // Some Chrome versions keep the transport alive after close. Bound cleanup.
    const exitCode = process.exitCode || 0;
    const timeout = setTimeout(() => process.exit(exitCode), 3000);
    try { if (browser) await browser.close(); } finally { clearTimeout(timeout); }
  });
