/** SVG原本をChromiumで描画し、2倍解像度の掲載用PNGを書き出す。
 *  引数なし：sources/ の全SVG。図の名前（例：01-scan-and-filter）：sources/ のその図だけ。
 *  .svg で終わるパス（例：parts/figure-parts.svg）：そのSVGを、同じ場所のPNGへ書き出す。 */
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

async function listTargets(root, sources, args) {
  if (args.length === 0) {
    const names = (await fs.readdir(sources)).filter(name => name.endsWith('.svg')).sort();
    return names.map(name => ({ svg: path.join(sources, name), png: path.join(root, name.replace(/\.svg$/, '.png')) }));
  }
  return args.map(arg => (arg.endsWith('.svg')
    ? { svg: path.join(root, arg), png: path.join(root, arg.replace(/\.svg$/, '.png')) }
    : { svg: path.join(sources, `${arg}.svg`), png: path.join(root, `${arg}.png`) }));
}

async function main() {
  const root = __dirname;
  const sources = path.join(root, 'sources');
  const targets = await listTargets(root, sources, process.argv.slice(2));
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ deviceScaleFactor: 2 });
    for (const { svg, png } of targets) {
      await page.goto(pathToFileURL(svg).href);
      await page.evaluate(() => document.fonts.ready);
      await page.locator('svg').screenshot({ path: png, animations: 'disabled' });
      console.log(path.relative(process.cwd(), png));
    }
  } finally {
    await browser.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
