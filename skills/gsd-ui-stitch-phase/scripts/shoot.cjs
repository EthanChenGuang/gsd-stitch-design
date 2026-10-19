#!/usr/bin/env node
// Render static HTML files to PNG with Playwright (Chromium).
// Usage: node shoot.cjs [--width N] [--height N] [--scale N] [--wait MS] [--check] file.html [more.html ...]
// Defaults: 390 x 844 @2x, 600 ms wait. Writes <same path>.png next to each input.
'use strict';

const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { execSync } = require('node:child_process');

const USAGE =
  'Usage: node shoot.cjs [--width N] [--height N] [--scale N] [--wait MS] [--check] file.html [more.html ...]\n' +
  '  defaults: --width 390 --height 844 --scale 2 --wait 600';

const HINT =
  'Playwright (chromium) is not available. Install it in the project:\n' +
  '  npm i -D playwright\n' +
  '  npx playwright install chromium';

function parseArgs(argv) {
  const opts = { width: 390, height: 844, scale: 2, wait: 600, check: false, files: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') {
      opts.check = true;
    } else if (a === '--width' || a === '--height' || a === '--scale' || a === '--wait') {
      const v = Number(argv[++i]);
      if (!Number.isFinite(v) || v < 0) {
        console.error('Invalid value for ' + a + '\n' + USAGE);
        process.exit(2);
      }
      opts[a.slice(2)] = v;
    } else if (a.startsWith('--')) {
      console.error('Unknown option: ' + a + '\n' + USAGE);
      process.exit(2);
    } else {
      opts.files.push(a);
    }
  }
  return opts;
}

function loadPlaywright() {
  for (const name of ['playwright', '@playwright/test']) {
    try {
      return require(require.resolve(name, { paths: [process.cwd()] }));
    } catch {
      // not resolvable from here; try the next location
    }
  }
  for (const name of ['playwright', '@playwright/test']) {
    try {
      return require(name);
    } catch {
      // not resolvable from here; try the next location
    }
  }
  try {
    const root = execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    if (root) return require(require.resolve('playwright', { paths: [root] }));
  } catch {
    // npm not available or playwright not installed globally
  }
  return null;
}

async function settleFonts(page, waitMs) {
  await page.evaluate(() => document.fonts.ready);
  // Load every distinct font style/weight/family used by an element that has text, with the page text.
  await page.evaluate(async () => {
    const text = document.body ? document.body.innerText : '';
    const seen = new Set();
    const specs = [];
    for (const el of document.querySelectorAll('body *')) {
      const hasText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
      if (!hasText) continue;
      const cs = getComputedStyle(el);
      const key = cs.fontStyle + '|' + cs.fontWeight + '|' + cs.fontFamily;
      if (seen.has(key)) continue;
      seen.add(key);
      specs.push(cs.fontStyle + ' ' + cs.fontWeight + ' 16px ' + cs.fontFamily);
    }
    await Promise.all(specs.map((s) => document.fonts.load(s, text).catch(() => [])));
  });
  await page.evaluate(() => document.fonts.ready);
  if (waitMs > 0) await page.waitForTimeout(waitMs);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.check && opts.files.length === 0) {
    console.error(USAGE);
    process.exit(2);
  }

  const pw = loadPlaywright();
  if (!pw || !pw.chromium) {
    console.error(HINT);
    process.exit(1);
  }

  let browser;
  try {
    browser = await pw.chromium.launch();
  } catch (e) {
    console.error('Could not launch chromium: ' + (e && e.message ? e.message.split('\n')[0] : e));
    console.error(HINT);
    process.exit(1);
  }

  if (opts.check) {
    await browser.close();
    console.log('ok');
    return;
  }

  let failed = 0;
  const ctx = await browser.newContext({
    viewport: { width: opts.width, height: opts.height },
    deviceScaleFactor: opts.scale,
  });
  const page = await ctx.newPage();
  for (const f of opts.files) {
    try {
      const abs = path.resolve(f);
      if (!require('node:fs').existsSync(abs)) throw new Error('file not found');
      await page.goto(pathToFileURL(abs).href, { waitUntil: 'networkidle' }).catch(() => {});
      await settleFonts(page, opts.wait);
      const fam = await page.evaluate(() =>
        [...new Set([...document.fonts].filter((x) => x.status === 'loaded').map((x) => x.family))].join(',')
      );
      const out = f.replace(/\.html?$/i, '') + '.png';
      await page.screenshot({ path: out });
      console.log('✓', f, '| fonts:', fam || 'system');
    } catch (e) {
      failed++;
      console.error('✗', f, '-', e && e.message ? e.message.split('\n')[0] : e);
    }
  }
  await browser.close();
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e && e.message ? e.message : e);
  process.exit(1);
});
