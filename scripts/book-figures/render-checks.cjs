/** SVG をブラウザで描いて測る検査。check-figures.cjs から呼ぶ。
 *  見るのは次の四つ。
 *  - 文字が、すぐ下に描いた図形（なければ画像の外枠）からはみ出していないか
 *  - 文字どうしが重なっていないか
 *  - 矢じりが文字に触れていないか
 *  - 見出し（最初の text）のすぐ下に、副題のような文字がないか
 *  文字の囲みは、rect・circle・ellipse・polygon と class="step" の path のうち、
 *  「文字の中心を含み、文字より前に描かれたもので、最後に描かれたもの」とする。 */
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const OPTIONS = {
  margin: 3, // 囲みの線の内側に、左右それぞれ最低限ほしい余白（SVG 単位）
  tolerance: 2, // 縦横ともこの値以下の重なりは、字形の余白による誤差とみなす
  subtitleGap: 24, // 見出しの下端からこの距離までに上端がある文字を、副題の候補にする
  subtitleLeft: 100, // 副題の候補にする文字の左端の上限（左寄せの文字だけを見る）
};

// ブラウザの中で実行する関数。問題を文の配列で返す。関数の外の変数は使えない。
function inspectPage(options) {
  const svg = document.querySelector('svg');
  const viewBox = svg.viewBox.baseVal;
  const toBox = b => ({ left: b.x, right: b.x + b.width, top: b.y, bottom: b.y + b.height });
  const quote = el => `「${el.textContent.trim().replace(/\s+/g, ' ').slice(0, 30)}」`;
  const overlaps = (a, b) => Math.min(a.right, b.right) - Math.max(a.left, b.left) > options.tolerance
    && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > options.tolerance;
  const texts = [...svg.querySelectorAll('text')].map(el => ({ el, box: toBox(el.getBBox()) }));
  const problems = [];

  const canvas = { left: 0, right: viewBox.width, top: 0, bottom: viewBox.height };
  const isBackground = b => b.left <= 0 && b.top <= 0 && b.right >= viewBox.width && b.bottom >= viewBox.height;
  const shapes = [...svg.querySelectorAll('rect, circle, ellipse, polygon, path.step')]
    .map(el => ({ el, box: toBox(el.getBBox()) }))
    .filter(shape => !isBackground(shape.box));
  for (const text of texts) {
    const cx = (text.box.left + text.box.right) / 2;
    const cy = (text.box.top + text.box.bottom) / 2;
    const beneath = shapes.filter(shape => (shape.el.compareDocumentPosition(text.el) & Node.DOCUMENT_POSITION_FOLLOWING)
      && shape.box.left <= cx && cx <= shape.box.right && shape.box.top <= cy && cy <= shape.box.bottom);
    const inner = beneath.length > 0 ? beneath[beneath.length - 1].box : canvas;
    const margin = inner === canvas ? 0 : options.margin;
    const over = [];
    if (text.box.left < inner.left + margin) over.push(`左 ${(inner.left + margin - text.box.left).toFixed(1)}`);
    if (text.box.right > inner.right - margin) over.push(`右 ${(text.box.right - inner.right + margin).toFixed(1)}`);
    if (text.box.top < inner.top) over.push(`上 ${(inner.top - text.box.top).toFixed(1)}`);
    if (text.box.bottom > inner.bottom) over.push(`下 ${(text.box.bottom - inner.bottom).toFixed(1)}`);
    if (over.length > 0) problems.push(`文字がはみ出している（${over.join('、')}）: ${quote(text.el)}`);
  }

  for (let i = 0; i < texts.length; i += 1) {
    for (let j = i + 1; j < texts.length; j += 1) {
      if (overlaps(texts[i].box, texts[j].box)) problems.push(`文字が重なっている: ${quote(texts[i].el)}と${quote(texts[j].el)}`);
    }
  }

  for (const line of svg.querySelectorAll('path, line, polyline')) {
    const reference = getComputedStyle(line).markerEnd;
    const id = reference && reference !== 'none' ? (reference.match(/#([^")]+)/) || [])[1] : null;
    const marker = id ? svg.querySelector(`marker#${CSS.escape(id)}`) : null;
    if (!marker) continue;
    const total = line.getTotalLength();
    const end = line.getPointAtLength(total);
    const before = line.getPointAtLength(Math.max(0, total - 0.5));
    const angle = Math.atan2(end.y - before.y, end.x - before.x);
    const scale = marker.getAttribute('markerUnits') === 'userSpaceOnUse' ? 1 : parseFloat(getComputedStyle(line).strokeWidth);
    const read = (name, fallback) => parseFloat(marker.getAttribute(name) ?? fallback);
    const [width, height, refX, refY] = [read('markerWidth', 3), read('markerHeight', 3), read('refX', 0), read('refY', 0)];
    const corners = [[0, 0], [width, 0], [width, height], [0, height]].map(([x, y]) => {
      const dx = (x - refX) * scale;
      const dy = (y - refY) * scale;
      return { x: end.x + dx * Math.cos(angle) - dy * Math.sin(angle), y: end.y + dx * Math.sin(angle) + dy * Math.cos(angle) };
    });
    const head = {
      left: Math.min(...corners.map(p => p.x)), right: Math.max(...corners.map(p => p.x)),
      top: Math.min(...corners.map(p => p.y)), bottom: Math.max(...corners.map(p => p.y)),
    };
    for (const text of texts) if (overlaps(head, text.box)) problems.push(`矢じりが文字に触れている: ${quote(text.el)}`);
  }

  const heading = texts[0];
  if (heading) {
    for (const text of texts.slice(1)) {
      if (text.el.classList.contains('tag')) continue;
      const nearTop = text.box.top >= heading.box.bottom - 1 && text.box.top <= heading.box.bottom + options.subtitleGap;
      if (nearTop && text.box.left < options.subtitleLeft) problems.push(`見出しのすぐ下に副題のような文字がある: ${quote(text.el)}`);
    }
  }
  return problems;
}

// SVG のパスの配列を受け取り、パスをキー、問題の配列を値にした Map を返す。ブラウザは1回だけ起動する。
async function inspectFigures(svgPaths) {
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const results = new Map();
    for (const svgPath of svgPaths) {
      await page.goto(pathToFileURL(path.resolve(svgPath)).href);
      await page.evaluate(() => document.fonts.ready);
      results.set(svgPath, await page.evaluate(inspectPage, OPTIONS));
    }
    return results;
  } finally {
    await browser.close();
  }
}

module.exports = { inspectFigures, OPTIONS };
