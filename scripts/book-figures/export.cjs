/** SVG原本をChromiumで描画し、2倍解像度の掲載用PNGを書き出す。 */
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

async function main() {
  const root = path.resolve(__dirname, '../../images/postgresql-structures-explain');
  const sources = path.join(root, 'sources');
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ deviceScaleFactor: 2 });
    for (const name of (await fs.readdir(sources)).filter(n => n.endsWith('.svg')).sort()) {
      await page.goto(pathToFileURL(path.join(sources, name)).href);
      await page.evaluate(() => document.fonts.ready);
      const svg = page.locator('svg');
      const pngPath = path.join(root, name.replace(/\.svg$/, '.png'));
      await svg.screenshot({ path: pngPath, animations: 'disabled' });
      console.log(path.relative(process.cwd(), pngPath));
    }
  } finally {
    await browser.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
