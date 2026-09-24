/** SVG原本をChromiumで描画し、2倍解像度の掲載用PNGを書き出す。
 *  引数なし：sources/ の全SVG。図の名前（例：01-scan-and-filter）：sources/ のその図だけ。
 *  .svg で終わるパス（images/postgresql-query-journey/ からの相対。例：parts/figure-parts.svg）：
 *  そのSVGを同じ場所のPNGへ書き出す。sources/ の中のSVGは、名前で渡したときと同じく画像の置き場所へ書き出す。 */
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '../../images/postgresql-query-journey');
const SOURCES = path.join(ROOT, 'sources');

function targetFor(svg) {
  const dir = path.dirname(svg) === SOURCES ? ROOT : path.dirname(svg);
  return { svg, png: path.join(dir, path.basename(svg).replace(/\.svg$/, '.png')) };
}

async function listTargets(args) {
  if (args.length === 0) {
    const names = (await fs.readdir(SOURCES)).filter(name => name.endsWith('.svg')).sort();
    return names.map(name => targetFor(path.join(SOURCES, name)));
  }
  return args.map(arg => targetFor(arg.endsWith('.svg') ? path.join(ROOT, arg) : path.join(SOURCES, `${arg}.svg`)));
}

async function main() {
  const targets = await listTargets(process.argv.slice(2));
  const missing = [];
  for (const { svg } of targets) {
    await fs.access(svg).catch(() => missing.push(path.relative(process.cwd(), svg)));
  }
  if (missing.length > 0) throw new Error(`SVG がありません: ${missing.join(', ')}`);
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
main().catch(error => { console.error(error.message || error); process.exitCode = 1; });
