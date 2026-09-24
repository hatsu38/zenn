/** 図が FIGURE-PLAN.md 4章の約束を満たしているかを確かめる。
 *  使い方：node scripts/book-figures/check-figures.cjs 01-scan-and-filter 05-limit-bands
 *          node scripts/book-figures/check-figures.cjs --all */
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const IMAGE_DIR = path.join(ROOT, 'images/postgresql-query-journey');
const BOOK_DIR = path.join(ROOT, 'books/postgresql-query-journey');
const MIN_FONT_SIZE = 22;
const MAX_ASPECT_RATIO = 1.3;
const DISCLAIMER_PATTERNS = [/ではありません/, /ではない/, /学ぶきっかけ/, / ／ /, /※/, /説明用/, /省略/, /模式/, /架空/, /再現していません/];

// SVGの中の font-size（属性とスタイルの両方）のうち、minSize より小さい値を、出てきた順に返す。
// <style> で定義しただけで使っていないクラスも数える（厳しめ）。px 以外の単位は数字だけを見るので、
// 0.8em のような値は小さいと判定され、人の確認に回る。
function findSmallFonts(svgText, minSize) {
  const sizes = [...svgText.matchAll(/font-size(?:\s*=\s*["']|\s*:\s*)([\d.]+)/g)].map(match => Number(match[1]));
  return sizes.filter(size => size < minSize);
}

function readViewBox(svgText) {
  const match = svgText.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
  return match ? { width: Number(match[1]), height: Number(match[2]) } : null;
}

function findDisclaimers(svgText) {
  const texts = [...svgText.matchAll(/<text\b[^>]*>([\s\S]*?)<\/text>/g)].map(m => m[1].replace(/<[^>]+>/g, ''));
  return texts.filter(text => DISCLAIMER_PATTERNS.some(pattern => pattern.test(text)));
}

function findReference(name) {
  const chapters = fs.readdirSync(BOOK_DIR).filter(file => /^\d\d-.+\.md$/.test(file)).sort();
  for (const file of chapters) {
    const lines = fs.readFileSync(path.join(BOOK_DIR, file), 'utf8').split('\n');
    const index = lines.findIndex(line => line.includes(`/images/postgresql-query-journey/${name}.png`));
    if (index === -1) continue;
    const match = lines[index].match(/^!\[([^\]]*)\]\([^)\s]+(?: =(\d+)x)?\)/);
    return {
      file,
      line: index + 1,
      alt: match ? match[1] : '',
      widthSpec: match && match[2] ? Number(match[2]) : null,
      caption: lines[index + 1] || '',
    };
  }
  return null;
}

function checkFigure(name, catalog) {
  const svgPath = path.join(IMAGE_DIR, 'sources', `${name}.svg`);
  if (!fs.existsSync(svgPath)) return [`SVG がない: ${path.relative(ROOT, svgPath)}`];
  const svg = fs.readFileSync(svgPath, 'utf8');
  const problems = [];

  const small = findSmallFonts(svg, MIN_FONT_SIZE);
  if (small.length > 0) problems.push(`文字が小さい（${MIN_FONT_SIZE}未満）: ${[...new Set(small)].join(', ')}`);

  const box = readViewBox(svg);
  const ref = findReference(name);
  if (!box) problems.push('viewBox が読めない');
  else if (box.height / box.width > MAX_ASPECT_RATIO && !(ref && ref.widthSpec)) {
    problems.push(`縦に長い（縦横比 ${(box.height / box.width).toFixed(2)}）。分割するか、本文で =520x などの幅を指定する`);
  }

  const disclaimers = findDisclaimers(svg);
  if (disclaimers.length > 0) problems.push(`画像内に断り書き: ${disclaimers.join(' / ')}`);

  const pngPath = path.join(IMAGE_DIR, `${name}.png`);
  if (!fs.existsSync(pngPath)) problems.push('PNG がない（書き出していない）');
  else if (fs.statSync(pngPath).mtimeMs + 2000 < fs.statSync(svgPath).mtimeMs) problems.push('PNG が SVG より古い（書き出し忘れ）');

  const entry = catalog.find(item => item.name === name);
  if (!entry) problems.push('catalog.json に登録がない');

  if (!ref) problems.push('本文から参照されていない');
  else {
    const where = `${ref.file}:${ref.line}`;
    if (!/^\*.+\*$/.test(ref.caption)) problems.push(`${where} の直後にキャプションがない`);
    if (!ref.alt) problems.push(`${where} の代替テキストが空`);
    else if (entry && ref.alt === entry.title) problems.push(`${where} の代替テキストが画像の見出しと同じ`);
  }
  return problems;
}

function main() {
  const args = process.argv.slice(2);
  const catalog = JSON.parse(fs.readFileSync(path.join(IMAGE_DIR, 'catalog.json'), 'utf8'));
  const names = args.includes('--all') ? catalog.map(item => item.name) : args;
  if (names.length === 0) {
    console.error('図の名前を指定するか、--all を付けてください');
    process.exitCode = 2;
    return;
  }
  let failed = 0;
  for (const name of names) {
    const problems = checkFigure(name, catalog);
    if (problems.length === 0) {
      console.log(`✓ ${name}`);
      continue;
    }
    failed += 1;
    console.log(`✗ ${name}`);
    for (const problem of problems) console.log(`    - ${problem}`);
  }
  console.log(`\n${names.length}枚中 ${names.length - failed}枚が約束を満たしています`);
  process.exitCode = failed > 0 ? 1 : 0;
}

if (require.main === module) main();
module.exports = { findSmallFonts, readViewBox, findDisclaimers };
