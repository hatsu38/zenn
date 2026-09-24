const { test, before } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { inspectFigures } = require('./render-checks.cjs');

// 部品見本と同じ書体・矢じりを使う、見出しだけの小さな SVG に body を足す
function figure(body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="400" viewBox="0 0 640 400">
  <defs><marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker></defs>
  <style>text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:22px;fill:#243b50}.h{font-size:30px;font-weight:700}.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}</style>
  <rect width="640" height="400" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">見出し</text>
  ${body}
</svg>`;
}

const CASES = {
  clean: '',
  overflow: '<rect x="24" y="100" width="120" height="40" fill="#fff"/><text x="30" y="128">枠より長いラベルです</text>',
  fits: '<rect x="24" y="100" width="300" height="40" fill="#fff"/><text x="30" y="128">収まるラベル</text>',
  overlap: '<text x="24" y="120">上の文字</text><text x="40" y="126">下の文字</text>',
  stacked: '<text x="24" y="120">1行目の文字</text><text x="24" y="150">2行目の文字</text>',
  arrowTouch: '<path d="M100 200 H300" class="flow"/><text x="296" y="208">終点のすぐ先</text>',
  arrowClear: '<path d="M100 200 H300" class="flow"/><text x="340" y="208">離れたラベル</text>',
  subtitle: '<text x="24" y="82">見出しの下の説明文</text>',
  content: '<text x="24" y="120">見出しから離れた文字</text>',
};

let results;
before(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'render-checks-'));
  const files = Object.fromEntries(Object.entries(CASES).map(([name, body]) => {
    const file = path.join(dir, `${name}.svg`);
    fs.writeFileSync(file, figure(body));
    return [name, file];
  }));
  const found = await inspectFigures(Object.values(files));
  results = Object.fromEntries(Object.entries(files).map(([name, file]) => [name, found.get(file)]));
  fs.rmSync(dir, { recursive: true, force: true });
});

test('inspectFigures：見出しだけの図には問題がない', () => {
  assert.deepEqual(results.clean, []);
});

test('inspectFigures：枠からはみ出した文字を拾い、収まる文字は拾わない', () => {
  assert.equal(results.overflow.length, 1);
  assert.match(results.overflow[0], /^文字がはみ出している（右 [\d.]+）: 「枠より長いラベルです」$/);
  assert.deepEqual(results.fits, []);
});

test('inspectFigures：重なった文字を拾い、行間を空けた2行は拾わない', () => {
  assert.deepEqual(results.overlap, ['文字が重なっている: 「上の文字」と「下の文字」']);
  assert.deepEqual(results.stacked, []);
});

test('inspectFigures：矢じりに触れる文字を拾い、離れた文字は拾わない', () => {
  assert.deepEqual(results.arrowTouch, ['矢じりが文字に触れている: 「終点のすぐ先」']);
  assert.deepEqual(results.arrowClear, []);
});

test('inspectFigures：見出しのすぐ下の左寄せの文字を副題として拾う', () => {
  assert.deepEqual(results.subtitle, ['見出しのすぐ下に副題のような文字がある: 「見出しの下の説明文」']);
  assert.deepEqual(results.content, []);
});
