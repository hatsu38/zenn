/** 紙面用に、図の原本（SVG）を4倍の解像度でPNGへ書き出し、build/src/images の同名のPNGを置き換える。
 *  掲載用のPNG（横1280px）はB5の本文幅（146mm）で約220dpiなので、印刷に向けて約445dpiにする。
 *  先に `node convert.mjs` で build/src/images を作ってから実行する。
 *  NODE_PATH=../../scripts/book-figures/node_modules node export-hires.cjs */
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

const imagesDir = path.join(__dirname, 'build', 'src', 'images');
const sourcesDir = path.join(__dirname, '..', '..', 'images', 'postgresql-query-journey', 'sources');

(async () => {
  const names = fs.readdirSync(imagesDir).filter((name) => name.endsWith('.png'));
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ deviceScaleFactor: 4 });
  let replaced = 0;
  for (const name of names) {
    const svg = path.join(sourcesDir, name.replace(/\.png$/, '.svg'));
    if (!fs.existsSync(svg)) {
      console.warn(`SVG がないので掲載用のPNGのまま: ${name}`);
      continue;
    }
    await page.goto(pathToFileURL(svg).href);
    await page.evaluate(() => document.fonts.ready);
    await page.locator('svg').screenshot({ path: path.join(imagesDir, name), animations: 'disabled' });
    replaced++;
  }
  await browser.close();
  console.log(`${replaced} 枚を4倍の解像度で書き出しました`);
})();
