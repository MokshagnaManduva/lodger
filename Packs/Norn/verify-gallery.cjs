// Usage: NODE_PATH=/path/to/node_modules node Packs/Norn/verify-gallery.cjs
// Requires Playwright with Chromium; it is not a gallery runtime dependency.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(pathToFileURL(path.join(__dirname, 'gallary.html')).href);
    await page.waitForFunction(() => document.querySelector('#load-status').textContent === '6 / 6 studies ready');
    assert.equal(await page.locator('.card').count(), 6);
    assert.equal(await page.locator('#speed').inputValue(), '1');
    assert.equal(await page.locator('#speed option').count(), 3);
    await page.click('#toggle-all');
    const paused = await page.locator('.frame-count').allTextContents();
    await page.waitForTimeout(400);
    assert.deepEqual(await page.locator('.frame-count').allTextContents(), paused);
    const first = page.locator('.card').first();
    await first.locator('.scrubber').fill('5');
    assert.equal(await first.locator('.frame-count').textContent(), '06 / 06');
    await first.locator('.step').click();
    assert.equal(await first.locator('.frame-count').textContent(), '01 / 06');
    await first.locator('.play').click();
    await page.waitForTimeout(700);
    assert.notEqual(await first.locator('.frame-count').textContent(), '01 / 06');
    await first.locator('.play').click();
    await first.locator('.scrubber').fill('0');
    await page.selectOption('#speed', '0.5');
    await first.locator('.play').click();
    await page.waitForTimeout(700);
    assert.equal(await first.locator('.frame-count').textContent(), '01 / 06');
    await first.locator('.play').click();
    await page.selectOption('#speed', '1');
    await page.selectOption('#background', 'dark');
    assert.equal(await page.locator('.stage[data-background="dark"]').count(), 6);
    await page.selectOption('#background', 'grid');
    assert.equal(await page.locator('.stage[data-background="grid"]').count(), 6);
    await page.selectOption('#background', 'paper');
    // Every keyframe should be a distinct rendered image, not a repeated standee.
    for (const card of await page.locator('.card').all()) {
      const frames = new Set();
      for (let i = 0; i < 6; i++) {
        await card.locator('.scrubber').fill(String(i));
        frames.add((await card.locator('canvas').screenshot()).toString('base64'));
      }
      assert.equal(frames.size, 6);
      await card.locator('.scrubber').fill('0');
    }
    await page.screenshot({ path: '/tmp/norn-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
    await page.screenshot({ path: '/tmp/norn-mobile.png', fullPage: true });
    const reduced = await browser.newPage({ reducedMotion: 'reduce' });
    await reduced.goto(pathToFileURL(path.join(__dirname, 'gallary.html')).href);
    await reduced.waitForFunction(() => document.querySelector('#load-status').textContent === '6 / 6 studies ready');
    assert.equal(await reduced.locator('#toggle-all').textContent(), 'Play all');
    assert.deepEqual(await reduced.locator('.frame-count').allTextContents(), Array(6).fill('01 / 06'));
    assert.deepEqual(errors, []);
    console.log('PASS: local-file assets, six distinct frames per study, play/pause, step/wrap, scrub, tempo, backgrounds, mobile overflow, reduced motion, no JS errors.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
