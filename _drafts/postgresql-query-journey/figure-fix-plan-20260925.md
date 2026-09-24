# 誤りを直す8枚と検査の道具 実装計画（横展開の段階A）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設計書7章の「誤解を招く図」のうち残る8枚を、第1〜2章の試作で決めた型で直す。あわせて、横展開の全部の図で使う検査（文字のはみ出し・重なり・矢じりとの接触・副題・文）を `check-figures.cjs` に入れる。

**Architecture:** 検査は、SVG の文字列と本文で分かることを `scripts/book-figures/check-figures.cjs` で、描画して測ることを新しい `scripts/book-figures/render-checks.cjs` で調べる。図は1枚1タスクで、SVG 原本・PNG・本文（キャプション・代替テキスト・指定した前後の文）・catalog.json の自分の項目だけを直してコミットする。README・index.html・book-flow.html は最後のタスクでまとめて合わせる。

**Tech Stack:** SVG、Node.js（node:test）、Playwright 1.62.1（Chromium）、Zenn の Markdown、PostgreSQL 18.6（実測の確認だけ）。

## 横展開の全体の段取り

設計書（[FIGURE-PLAN.md](../../books/postgresql-query-journey/FIGURE-PLAN.md)）5章の順に進める。各段階を1つの PR にし、前の段階の PR の上に積む。

| 段階 | 中身 | 枚数 |
| --- | --- | --- |
| A（この計画） | 検査の道具と、7章の誤解を招く図の残り8枚 | 直し8 |
| B | 高優先度の新規図（`06-tree-levels`・`07-sort-bands`・`08-sort-vs-topn`・`09-loops`・`10-stats-to-rows`・`11-heap-fetches`・`12-plan-overview`） | 新規7 |
| C | 序章・第3〜4章の残り | 直し10、新規なし |
| D | 第5〜8章の残り | 直し11、新規3 |
| E | 第9〜12章の残り。技術の図が1章2〜3枚の目安を超える章は、新規図の統合・見送りをユーザーに確かめてから | 直し11、新規5以下 |

## Global Constraints

すべてのタスクに当てはまる。

- 出し先は Zenn だけ。本文の幅はスマホで約343px、PCで約700px。
- SVG は幅640、`viewBox="0 0 640 H"`、H は832以下（縦横比1.3以下）。
- `<defs>` と `<style>` は `images/postgresql-query-journey/parts/figure-parts.svg` からそのまま写す。クラスを足すのは部品見本にない形が要るときだけにし、足したら報告する。
- 背景は `<rect width="640" height="H" fill="#f5f7f9"/>`。見出しは `<text x="24" y="48" class="h">`。札（「模型」「実測」など）は右上に置き、右端を x=616 にそろえる。見出しと同じ行に置くときは、見出しとの間を12以上あける（入らないときは次の行の右端へ下げる）。「模型」の札は幅68（x=548）にする。
- `<title id="title">` の文字と見出しの文字と catalog.json の `title` を同じにする。
- 文字は `font-size` 22以上。部品見本のクラス（`.s`・`.m`・`.mono`・`.tag` は22、本文は24、見出しは30）を使う。
- 画像の中の文字は、見出し・札・部品の名前・焦点のラベル（試作の「行は出さない」のような短いもの）・矢印の動詞・出力の項目名と値だけ。副題・断り書き・他の章への参照・「。」で終わる文は置かない。
- 橙の太枠（`.hot`）は1枚に1か所。矢印は、実線の青緑（`.flow`）が行やデータ、破線の茶（`.req`）が要求、細い灰色（`.ref`）が参照・対応、太い白抜き（`.step`）が処理の段階・時間の順。
- 出力の項目名（`Heap Fetches` など）とノード名は等幅（`.mono`）で書く。
- 「索引」は使わず「Index」と書く。第3章の図と本文では「模型」を使わない（このタスク群では第3章に触れない）。
- 線や矢印は、重なる図形より後に描く。矢じりの近くのラベルは、矢じりの大きさ（線の太さ×10）の分だけ離す。
- 本文で直してよいのは、各タスクに書いたキャプション・代替テキスト・前後の文だけ。ほかの文は変えない。
- 数値は各タスクに書いた出典の値だけを使う。
- PNG は図の名前を付けて書き出す（`node images/postgresql-query-journey/export.cjs 図の名前`）。名前なしで実行すると全部の PNG を書き出し直してしまう。
- git worktree の中では Playwright が見つからないので、本体の node_modules を `NODE_PATH=/Users/hatsu/development/github.com/hatsu38/zenn/scripts/book-figures/node_modules` で指定する。
- コミットは日本語の Conventional Commits（例：`docs(query-journey): …`）。`Co-Authored-By` は付けない。署名は git の設定で自動で付く（`--no-gpg-sign` や `--no-verify` は使わない）。`git add` はパスを明示し、`.claude/worktrees/` は入れない。

## ファイルの構成

| ファイル | 役割 | 触るタスク |
| --- | --- | --- |
| `scripts/book-figures/render-checks.cjs`（新規） | 描画して測る検査（はみ出し・重なり・矢じり・副題） | 1 |
| `scripts/book-figures/render-checks.test.cjs`（新規） | その検査のテスト | 1 |
| `scripts/book-figures/check-figures.cjs` | 文字列の検査に「文」を足し、描画の検査を呼ぶ | 1 |
| `scripts/book-figures/check-figures.test.cjs` | 「文」の検査のテストを足す | 1 |
| `scripts/book-figures/package.json` | テストの対象に新しいテストを足す | 1 |
| `images/postgresql-query-journey/README.md` | 検査の説明 | 1、10 |
| `books/postgresql-query-journey/FIGURE-PLAN.md` | 4.4 の約束の言い方、7章の表の時期、10章の基準 | 1、10 |
| `books/postgresql-query-journey/ILLUSTRATION-GUIDE.md` | 検査の説明を1文足す | 1 |
| `images/postgresql-query-journey/sources/<名前>.svg` と `<名前>.png` | 図の原本と掲載画像 | 2〜9 |
| `images/postgresql-query-journey/parts/figure-parts.svg` と `.png` | 部品見本に共有バッファ・作業領域・値カードを足す | 4 |
| `books/postgresql-query-journey/0N-*.md` | キャプション・代替テキスト・指定した前後の文 | 2〜9 |
| `images/postgresql-query-journey/catalog.json` | 各図の `title` と `description` | 2〜9 |
| `images/postgresql-query-journey/index.html`・`books/postgresql-query-journey/book-flow.html` | 一覧（catalog.json から合わせる） | 10 |

## 実行の段取り

- Task 1 を先に終えてコミットする（Task 2〜9 が新しい検査を使うため）。
- Task 2〜9 は互いに独立している。同じ章のファイルを触るタスク（2と3、6と7、8と9）も、直す行が離れている。コントローラーは各タスクを git worktree で並行して進め、終わったものから作業ブランチへ cherry-pick する。README・index.html・book-flow.html は1行に複数の図が入るため、Task 2〜9 では触らない。
- Task 10 で一覧を合わせ、全体を確かめてから ship する。

---

### Task 1: 描画して測る検査を入れ、約束の言い方を直す

**Files:**
- Create: `scripts/book-figures/render-checks.cjs`
- Create: `scripts/book-figures/render-checks.test.cjs`
- Modify: `scripts/book-figures/check-figures.cjs`
- Modify: `scripts/book-figures/check-figures.test.cjs`
- Modify: `scripts/book-figures/package.json`
- Modify: `images/postgresql-query-journey/README.md`（「約束を確かめる」の節）
- Modify: `books/postgresql-query-journey/FIGURE-PLAN.md`（4.4 の最初の項目、10章の6項目め）
- Modify: `books/postgresql-query-journey/ILLUSTRATION-GUIDE.md`（「2026年9月24日：見るところが分かる図へ」の節）

**Interfaces:**
- Produces: `inspectFigures(svgPaths: string[]): Promise<Map<string, string[]>>`（render-checks.cjs。キーは渡したパス、値は問題の文の配列）、`findSentences(svgText: string): string[]`（check-figures.cjs）。`node scripts/book-figures/check-figures.cjs 名前…` が、文字列の検査と描画の検査の両方を行う。

- [ ] **Step 1: 描画の検査のテストを書く**

`scripts/book-figures/render-checks.test.cjs` を次の内容で作る。

```js
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `cd scripts/book-figures && node --test render-checks.test.cjs`
Expected: FAIL（`Cannot find module './render-checks.cjs'`）

- [ ] **Step 3: 描画の検査を書く**

`scripts/book-figures/render-checks.cjs` を次の内容で作る。

```js
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
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `cd scripts/book-figures && node --test render-checks.test.cjs`
Expected: `ℹ pass 5`、`ℹ fail 0`

- [ ] **Step 5: 「文」の検査のテストを足す**

`scripts/book-figures/check-figures.test.cjs` の3行目を次に置き換える。

```js
const { findSmallFonts, readViewBox, findDisclaimers, findSentences } = require('./check-figures.cjs');
```

ファイルの末尾に次を足す。

```js

test('findSentences：「。」で終わる文だけを拾う', () => {
  const svg = '<text>行の配置は省略した。</text><text>本42</text><text x="1">1行ずつ<tspan>比べる</tspan></text>';
  assert.deepEqual(findSentences(svg), ['行の配置は省略した。']);
});
```

Run: `cd scripts/book-figures && node --test check-figures.test.cjs`
Expected: FAIL（`findSentences is not a function`）

- [ ] **Step 6: check-figures.cjs に「文」の検査と描画の検査を入れる**

`scripts/book-figures/check-figures.cjs` を、次の5か所で書き換える。

(1) 先頭のコメントと require（1〜5行目）を次に置き換える。

```js
/** 図が FIGURE-PLAN.md 4章の約束を満たしているかを確かめる。
 *  SVG の文字列と本文から分かることはここで調べ、描画して測ることは render-checks.cjs で調べる。
 *  使い方：node scripts/book-figures/check-figures.cjs 01-scan-and-filter 05-limit-bands
 *          node scripts/book-figures/check-figures.cjs --all */
const fs = require('node:fs');
const path = require('node:path');
const { inspectFigures } = require('./render-checks.cjs');
```

(2) `function findReference(name) {` の直前に次を足す。

```js
// 画像の中の文字のうち、「。」で終わる文を返す。図の中には文を置かない約束のため。
function findSentences(svgText) {
  const texts = [...svgText.matchAll(/<text\b[^>]*>([\s\S]*?)<\/text>/g)].map(m => m[1].replace(/<[^>]+>/g, '').trim());
  return texts.filter(text => text.endsWith('。'));
}

```

(3) `checkFigure` の中の、断り書きの検査の2行の直後に次を足す。

```js

  const sentences = findSentences(svg);
  if (sentences.length > 0) problems.push(`画像内に文（「。」で終わる）: ${sentences.join(' / ')}`);
```

(4) `function main() {` から、ループの中の `if (problems.length === 0) {` までを次に置き換える。

```js
async function main() {
  const args = process.argv.slice(2);
  const catalog = JSON.parse(fs.readFileSync(path.join(IMAGE_DIR, 'catalog.json'), 'utf8'));
  const names = args.includes('--all') ? catalog.map(item => item.name) : args;
  if (names.length === 0) {
    console.error('図の名前を指定するか、--all を付けてください');
    process.exitCode = 2;
    return;
  }
  const svgPathOf = name => path.join(IMAGE_DIR, 'sources', `${name}.svg`);
  const rendered = await inspectFigures(names.map(svgPathOf).filter(svgPath => fs.existsSync(svgPath)));
  let failed = 0;
  for (const name of names) {
    const problems = [...checkFigure(name, catalog), ...(rendered.get(svgPathOf(name)) || [])];
    if (problems.length === 0) {
```

(5) 末尾の2行を次に置き換える。

```js
if (require.main === module) {
  main().catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
module.exports = { findSmallFonts, readViewBox, findDisclaimers, findSentences };
```

- [ ] **Step 7: テストの対象を足し、全部のテストが通ることを確かめる**

`scripts/book-figures/package.json` の `"test"` を次にする。

```json
    "test": "node --test check-figures.test.cjs render-checks.test.cjs"
```

Run: `cd scripts/book-figures && npm test`
Expected: `ℹ pass 12`、`ℹ fail 0`

- [ ] **Step 8: 試作8枚が ✓ のままで、直す前の8枚が ✗ になることを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window 01-explain-stages 01-scan-and-filter 01-index-to-row 05-growing-library 05-linear-scan 05-limit-search 05-limit-bands`
Expected: 最後の行が `8枚中 8枚が約束を満たしています`

Run: `node scripts/book-figures/check-figures.cjs 03-pages-and-rows 09-title-lookup`
Expected: 2枚とも ✗。`見出しのすぐ下に副題のような文字がある` を含む（`09-title-lookup` は「読了記録と、本の一覧を対応させたい。」で、`画像内に文` も出る）

- [ ] **Step 9: README の「約束を確かめる」の節を書き換える**

`images/postgresql-query-journey/README.md` の「## 約束を確かめる」から、次の「## 図の一覧を作り直す」の直前までを、次に置き換える。

````md
## 約束を確かめる

図が[設計書](../../books/postgresql-query-journey/FIGURE-PLAN.md)4章の約束を満たしているかを確かめます。SVGと本文からは、文字の大きさ、縦横比、画像内の断り書きと文（「。」で終わる文字）、PNGの書き出し、catalog.jsonへの登録、本文からの参照とキャプション・代替テキストを調べます。さらにChromiumで描画して、文字のはみ出し（すぐ下に描いた図形から）、文字どうしの重なり、矢じりと文字の接触、見出しのすぐ下の副題を測ります。

```sh
node scripts/book-figures/check-figures.cjs 01-scan-and-filter
```

`--all`を付けると全部の図を確かめます。描き直す前の図は約束を満たしていないので、`--all`では多くの図が✗になります。git worktreeの中で実行するときは、Playwrightを入れた本体の`scripts/book-figures/node_modules`を`NODE_PATH`で指定します。

````

- [ ] **Step 10: 約束の言い方を直す**

`books/postgresql-query-journey/FIGURE-PLAN.md` の4.4の最初の項目

```md
- 画像の中に置くのは、短い見出し（15字程度まで）と「模型」「実測（日付）」の札だけ。副題と注意書きは置かない。
```

を、次の3項目に置き換える。

```md
- 画像の中の文字は、見出し（15字程度まで）・札（「模型」「実測（日付）」など）・部品の名前・焦点のラベル・矢印の動詞・出力の項目名と値に限る。副題・断り書き・他の章への参照・「。」で終わる文は置かず、要るものはキャプションへ回す（2026-09-25、試作で「札だけ」が図の中のラベルと字面上ぶつかったため言い換えた）。
- 「索引」は使わず「Index」と書く（AGENTS.mdの約束）。第3章の図と本文では「模型」を使わない。2026-09-25の#13で「仮に置いた数」「説明するための図」に言い換えたため、第3章の図には「模型」の札を付けず、キャプションに「説明するための図」と書く。
- `node scripts/book-figures/check-figures.cjs 図の名前`で✓になることを確かめる。描画して、文字のはみ出し・文字どうしの重なり・矢じりと文字の接触・見出しのすぐ下の副題も測る。
```

同じファイルの10章の項目

```md
- 画像の中は短い見出しと札だけで、文字はSVGで22以上。
```

を次に置き換える。

```md
- 画像の中の文字は4.4の範囲（見出し・札・部品の名前・焦点のラベル・矢印の動詞・出力の項目名と値）だけで、文字はSVGで22以上。`check-figures.cjs`で✓になる。
```

`books/postgresql-query-journey/ILLUSTRATION-GUIDE.md` の「## 2026年9月24日：見るところが分かる図へ」の節の文

```md
約束を満たしているかは`node scripts/book-figures/check-figures.cjs 図の名前`で確かめる。
```

を次に置き換える。

```md
約束を満たしているかは`node scripts/book-figures/check-figures.cjs 図の名前`で確かめる。この検査は図を描画して、文字のはみ出し・重なり・矢じりとの接触・見出しのすぐ下の副題も測る。
```

- [ ] **Step 11: コミットする**

```bash
git add scripts/book-figures/render-checks.cjs scripts/book-figures/render-checks.test.cjs scripts/book-figures/check-figures.cjs scripts/book-figures/check-figures.test.cjs scripts/book-figures/package.json images/postgresql-query-journey/README.md books/postgresql-query-journey/FIGURE-PLAN.md books/postgresql-query-journey/ILLUSTRATION-GUIDE.md
git commit -m "feat(book-figures): 図を描画して、文字のはみ出し・重なり・矢じり・副題を測る" -m "試作では、文字のはみ出しと矢じりとの接触を、実装担当とレビュー担当の両方が目で見落とした。横展開の図は check-figures.cjs で測れるようにする。あわせて「。」で終わる文を拾い、約束の言い方を「画像の中の文字は、見出し・札・部品の名前・矢印の動詞・出力の項目名と値に限る」に直した。"
```

---

### 図のタスクに共通する手順（Task 2〜9）

各図のタスクは、次の手順で進める。図ごとの中身は各タスクに書く。

1. 読む：各タスクの「本文」に書いた行の前後30行、今の SVG と PNG、部品見本（`images/postgresql-query-journey/parts/figure-parts.svg` と `.png`）。
2. SVG を書く：`images/postgresql-query-journey/sources/<名前>.svg` を丸ごと書き直す。先頭は次の形にする（H は高さ）。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="H" viewBox="0 0 640 H" role="img" aria-labelledby="title">
  <title id="title">見出しと同じ文字</title>
  <defs>（部品見本の defs をそのまま）</defs>
  <style>（部品見本の style をそのまま）</style>
  <rect width="640" height="H" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">見出し</text>
```

3. 書き出す：`NODE_PATH=/Users/hatsu/development/github.com/hatsu38/zenn/scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs <名前>`
4. 本文を直す：各タスクの Python を、リポジトリの直下で実行する（置き換え元が1回だけあることを確かめてから置き換える）。
5. catalog.json の自分の項目の `title` と `description` を、各タスクの値にする。ほかの項目と README・index.html・book-flow.html は触らない。
6. 確かめる：`NODE_PATH=… node scripts/book-figures/check-figures.cjs <名前>` が ✓。✗ なら直して 3 からやり直す。
7. 見る：PNG を原寸で開き、さらに `magick images/postgresql-query-journey/<名前>.png -resize 686x /tmp/<名前>-phone.png`（スマホの幅343pxを2倍で再現）を開く。焦点が一目で分かるか、文字が読めるか、矢印の向きと意味が約束どおりかを確かめる。
8. コミットする：`git add` に、SVG・PNG・直した章のファイル・catalog.json を明示して渡す。メッセージは各タスクに書いたもの。
9. 報告する：コミットのハッシュ、SVG の高さ、足したクラス（あれば）、手順7で見たことを書く。

---

### Task 2: 第4章 `03-pages-and-rows`（仕組み・描き直し）

**今の問題（設計書7章）:** 1ページ3行の模型で本4〜6をページ1に置いているが、36行後の ctid の出力では本1〜8がすべてページ0にある。1ページ3行では「1行のためにページ全体」の差も小さく見える。

**問い:** 観察用の表の1,000行は、8ページにどう入っているか。本5の1行が欲しいとき、何を読み込むか。

**数値と出典:** `_drafts/postgresql-query-journey/verification/chapter04-rows-per-page-20260925.log`（2026-09-25、PostgreSQL 18.6、検証用 DB `journey_million_20260923`、第4章と同じ手順で作った観察用の表を ROLLBACK）。表本体 65,536バイト＝8ページ。ページ0〜6に136行ずつ（本1〜136、137〜272、273〜408、409〜544、545〜680、681〜816、817〜952）、ページ7に48行（本953〜1000）。本5の ctid は (0,5)。

**描く:**
- 見出し：`本5の1行も、ページ0ごと読む`
- 右上に札「行数は実測」（`.real`、幅130程度）。
- 上段：枠「観察用の表 books（1,000行）」の中に、表のページ（部品見本の「表のページ」）を4列×2段で8枚。各ページの上に「ページ0」〜「ページ7」、中に行の範囲（「本1〜136」など）と行数（「136行」、ページ7は「48行」）。
- ページ0を焦点の太枠（`.hot`）にし、そばに「読み込む単位」。
- 下段：ページ0の拡大。行カードを「1　実験用の本 1」「⋮」「5　実験用の本 5」「⋮」「136　実験用の本 136」の順に並べ、本5だけ一致した行（`.match`）にする。本5のそばに「欲しいのは1行」、拡大の枠に「ページ0の136行を丸ごと読み込む」。上段のページ0と拡大を細い灰色の線（`.ref`、ラベル「拡大」）でつなぐ。

**焦点:** 上段のページ0の太枠。

**描かない:** ページの中の項目（行の場所の記録）と空き領域（次の節の話）、ctid の値（次の節で出す）。

**本文:** `books/postgresql-query-journey/04-pages-and-storage.md` の135〜140行目。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/04-pages-and-storage.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('ここでは説明のため、1ページに3行入る小さな模型を使います。実際に何行入るかは、行の大きさなどで変わります。',
     '観察用の表の1,000行が、8ページにどう入っているかを見てください。1ページに何行入るかは、行の大きさなどで変わります。'),
    ('![表の中にページ、ページの中に行](/images/postgresql-query-journey/03-pages-and-rows.png)',
     '![1,000行の表が8ページに分かれ、本5の入ったページ0を丸ごと読み込む](/images/postgresql-query-journey/03-pages-and-rows.png)'),
    ('*説明用の模型。1ページ3行は実際の容量ではありません。*',
     '*太枠のページ0と、その中の本5を見てください（ページごとの行数は2026年9月25日の実測）。*'),
    ('本5を読みたいなら、その本が入ったページ1が必要です。欲しいのが本5の1行だけでも、読み込むのは本4〜6の入ったページ1全体です。',
     '本5を読みたいなら、その本が入ったページ0が必要です。欲しいのが本5の1行だけでも、読み込むのは本1〜136の入ったページ0全体です。'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `本5の1行も、ページ0ごと読む`、`description` は `仕組み：観察用の表の8ページと行（行数は実測）`。

**コミット:** `docs(query-journey): 第4章のページと行の図を、実測どおりのページで描き直す`（本文：`1ページ3行の模型では、本4〜6をページ1に置いていて、後の ctid の出力（本1〜8がページ0）と食い違っていた。2026-09-25 に同じ手順の表で数えたページごとの行数（ページ0〜6に136行、ページ7に48行）で描き、図の前後の文とキャプションも合わせた。`）

---

### Task 3: 第4章 `03-row-width`（比較・手直し）

**今の問題（設計書7章）:** 拡大したページ内の行数（6本と2本）が実測と合わず、空きページもない。

**問い:** 同じ1,000行でも、行が長いとページはいくつ要るか。

**数値と出典:** Task 2 と同じログ。`size_short`（10文字）は65,536バイト＝8ページで、行が入っているのはページ0〜5（185行×5ページ＋75行）。ページ6・7は空き。`size_long`（200文字）は262,144バイト＝32ページで、行が入っているのはページ0〜29（34行×29ページ＋14行）。ページ30・31は空き。

**描く（比較の型。2段を同じ配置にする）:**
- 見出し：`同じ1,000行でも、8ページと32ページ`（今のまま）
- 札「実測」（`.real`）。見出しの右端が約570で右上に入らないので、1段目のラベルと同じ高さの右端（右端 x=616）に置く。
- 1段目：ラベル「短い行（10文字）」。ページのアイコン8個を横1列に。行の入った6個は中に横線（行）を描いた実線のページ、残り2個は破線（`.ghost`）で中に「空き」。下に「1ページに最大185行」と「8ページ＝65,536バイト」。
- 2段目：ラベル「長い行（200文字）」。同じ大きさのアイコン32個を16個×2列に。行の入った30個は実線、最後の2個は破線で「空き」。下に「1ページに最大34行」と「32ページ＝262,144バイト」。
- 2段目の「1ページに最大34行」を焦点の枠（`.hot`）にする。

**焦点:** 長い行は1ページに34行しか入らないこと。

**描かない:** 拡大したページ（今の図の拡大は外す）、行の中身、ページの中の配置。

**本文:** `books/postgresql-query-journey/04-pages-and-storage.md` の281〜282行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/04-pages-and-storage.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![長い行は同じページに入る数が少なくなり、1,000行を入れるページが増える](/images/postgresql-query-journey/03-row-width.png)',
     '![短い行は6ページに最大185行ずつ、長い行は30ページに最大34行ずつ入り、どちらの表にも行の入っていないページが2つある](/images/postgresql-query-journey/03-row-width.png)'),
    ('*総ページ数の8と32は今回の実測値。拡大したページ内の行数は説明用です。*',
     '*1ページに入る行の数（最大185行と34行）の差が、ページ数の差になっています。破線は行の入っていない空きページです（2026年9月25日の実測）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `同じ1,000行でも、8ページと32ページ`、`description` は `比較：行の長さとページ数（実測）`。

**コミット:** `docs(query-journey): 第4章の行幅の図を、実測のページごとの行数で描き直す`（本文：`拡大したページの行数（6本と2本）が実測と合わず、空きページもなかった。行が入るのは6ページと30ページで各2ページは空き、1ページの最大は185行と34行（2026-09-25 の実測）なので、ページのアイコンの数と破線の空きページで見せる。`）

---

### Task 4: 第5章 `04-memory-regions`（仕組み・描き直し）

**今の問題（設計書7章）:** 作業用メモリが接続に一つに見える。実際は並べ替えなどの処理ごとに使う。作業領域から共有バッファへの矢印の意味も分からない。

**問い:** 検索の途中の値はどこに置き、ページはどこに置くか。

**本文との約束（#13 で本文が図を読むようになった）:** 184行目は「図の上側の「8、3、5」は、接続Aと接続Bがそれぞれ並べ替えている途中の値です」、186行目は「下側の共有バッファにあるページP0〜P3は、どちらの接続からも使えます」と書く。上側に、接続Aと接続Bそれぞれの「8」「3」「5」、下側に共有バッファのページ「P0」〜「P3」を必ず描く。

**数値と出典:** 本文の `SHOW` の結果（`shared_buffers` 128MB、`work_mem` 4MB）。

**描く:**
- 見出し：`ページの保存場所と、計算の作業場所`（今のまま）
- 右上に札「模型」（`.model`）。
- 上段：枠「接続A」と「接続B」を左右に並べる。
  - 接続Aの中に作業領域（破線の枠）を2つ。1つめは「数える」で、中に値カード「本1 8」「本2 3」「本3 5」。2つめは「並べ替え」で、中に値カード「8」「3」「5」。
  - 接続Bの中に作業領域を1つ。「並べ替え」で、中に値カード「8」「3」「5」。
  - 接続Aの2つの破線の枠のそばに、焦点の札「処理ごとに1つ」（`.hot`）。
- 上段の下に凡例1行：破線の枠の小さな見本と `work_mem 4MB`（等幅）。
- 下段：大きな枠「共有バッファ」、枠の見出しの右に `shared_buffers 128MB`（等幅）。中に表のページ（部品見本の「表のページ」）を4枚、タブに「P0」「P1」「P2」「P3」。
- 接続A・Bの枠の下辺から共有バッファの枠へ、細い灰色の矢印（`.ref`）を1本ずつ。ラベル「ページを使う」。
- 値カード（小さな正方形）とページ（タブ付きの大きな枠）を別の形にする。
- 部品見本に、「作業領域（破線の枠）」「値カード」「共有バッファ」の3つを足す。部品見本の高さを必要なだけ伸ばし、`node images/postgresql-query-journey/export.cjs parts/figure-parts.svg` で見本の PNG も書き出す。足す見た目は、この図で使ったものと同じにする。

**焦点:** 接続Aに破線の枠が二つあること。

**描かない:** 並列処理、OSキャッシュ、プロセスとPID（第6章で描く）、作業領域どうしの「使い回さない」の×。

**本文:** `books/postgresql-query-journey/05-memory-and-buffers.md` の182〜183行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/05-memory-and-buffers.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![ページの保存場所と、計算の作業場所](/images/postgresql-query-journey/04-memory-regions.png)',
     '![接続Aは数える処理と並べ替えの作業領域を二つ、接続Bは並べ替えの一つを持ち、下の共有バッファのページP0〜P3は両方の接続が使う](/images/postgresql-query-journey/04-memory-regions.png)'),
    ('*基本の配置の模型。並列処理などは省略しています。*',
     '*接続Aに破線の枠が二つあることを見てください。作業領域は処理ごとに用意され、共有バッファだけを両方の接続で使います（模型）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `ページの保存場所と、計算の作業場所`、`description` は `仕組み：共有バッファと処理ごとの作業領域の模型`。

**コミット:** `docs(query-journey): 第5章のメモリの図で、作業領域を処理ごとの枠にする`（本文：`作業用メモリが接続に一つに見えていた。work_mem は並べ替えなどの処理ごとに使うので、接続Aに作業領域を二つ、接続Bに一つ描く。本文が読む「8、3、5」と「P0〜P3」は残した。部品見本に作業領域・値カード・共有バッファを足した。`）。部品見本の SVG と PNG も同じコミットに入れる。

---

### Task 5: 第6章 `02-query-stages`（仕組み・手直し）

**今の問題（設計書7章）:** 最後に「結果：id = 42…」の箱があり、EXPLAIN ANALYZE でも結果の行が返るように読める（第1章の説明と矛盾する）。縦横比も1.65ある。

**問い:** SQLの文字列は、バックエンドの中でどの段を通って結果の行になるか。EXPLAIN と EXPLAIN ANALYZE はどこまで進むか。

**描く（縦に進む。第1章 `01-explain-stages` と同じ部品と言葉を使う）:**
- 見出し：`SQLの文字列から、検索結果が返るまで`（今のまま）
- 札は付けない（処理の順番の概略で、模型でも実測でもないため。キャプションで「概略」と書く）。
- 最上段：入力のカード「受け取ったSQL」、中に等幅で2行 `SELECT id, title FROM books` と `WHERE title = '実験用の本 42';`。
- 中段：枠「バックエンドの中」。中に段の箱を4つ縦に並べる：「① 解析する」「② 書き換える」「③ 計画を作る」「④ 実行する」。箱と箱の間は太い白抜きの矢印（`.step` の形を縦向きにしたもの）。
  - ②の箱は破線（`.ghost`）にし、右に「今回は通過」。
  - ③の箱の2行目に `Planning Time`、④の箱の2行目に `Execution Time`（等幅）。
- 最下段：枠の外に出力のカード「結果の行を画面へ」、中に行カード「42　実験用の本 42」。④から太い白抜きの矢印でつなぐ。
- 右側に括弧を2本：`EXPLAIN` は①〜③の高さ、`EXPLAIN ANALYZE` は①〜④の高さ。括弧の名前は等幅。括弧の下端のそばに「③まで」「④まで」。
- `EXPLAIN ANALYZE` の括弧の下端（④の高さ）に、焦点の札「行は出さない」（`.hot`。第1章と同じ言葉）。

**焦点:** EXPLAIN ANALYZE の「行は出さない」。

**描かない:** 通信や表示の時間、プランナの中身、実行計画のノードと行の流れ（次の節の図で描く）。

**本文:** `books/postgresql-query-journey/06-process-and-execution.md` の114〜115行目。前後の文は変えない（113行目の「図の矢印は、処理が進む順番です。」がそのまま使える）。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/06-process-and-execution.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![題名検索のSQLが解析、書き換え、計画、実行を経て1行の結果になる](/images/postgresql-query-journey/02-query-stages.png)',
     '![SQLの文字列が解析・書き換え・計画・実行の4段を通って結果の行になり、EXPLAINは計画まで、EXPLAIN ANALYZEは実行まで進んで行は出さない](/images/postgresql-query-journey/02-query-stages.png)'),
    ('*通常のSELECTが通る処理の概略。実行計画内の行の流れとは別の図です。*',
     '*右の括弧で、EXPLAINとEXPLAIN ANALYZEがどの段まで進むかを見てください（処理の順番の概略）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `SQLの文字列から、検索結果が返るまで`、`description` は `仕組み：バックエンドの中の4つの段`。

**コミット:** `docs(query-journey): 第6章の処理の段の図で、EXPLAIN ANALYZE が行を出さないことを示す`（本文：`最後の「結果」の箱のせいで、EXPLAIN ANALYZE でも結果の行が返るように読めた。第1章の段階の図と同じ部品で、EXPLAIN は③まで、EXPLAIN ANALYZE は④までの括弧を付け、「行は出さない」を焦点にした。縦横比も1.3以下にした。`）

---

### Task 6: 第9章 `09-title-lookup`（問い・描き直し）

**今の問題（設計書7章）:** カードの色が、本番号2の記録と本1のような逆の組を対応させている。副題・注意書きもある。

**問い:** 記録にある本の番号から、どうやって題名を付けるか。

**数値と出典:** 本文18〜22行目の表（記録の本番号 2・1・2、本1＝星の図鑑、本2＝海の図鑑）。

**描く（問いの型。人物は描かない）:**
- 見出し：`本の番号だけでは、題名が分からない`（今のまま）
- 札は付けない。
- 左（または上）：画面の枠「最新の読了記録」。中に3行「本番号 2｜題名 ？」「本番号 1｜題名 ？」「本番号 2｜題名 ？」と、その下に「…20件」。
- 右（または下）：画面の外に表の枠「本の表 books（100万冊）」。中に行カード「1　星の図鑑」「2　海の図鑑」と「⋮」。
- 1行目の「本番号 2」から本の表の「2　海の図鑑」へ、細い灰色の矢印（`.ref`）を1本。ラベル「番号で探す」。
- 下に問いの箱「番号から、どうやって題名を付ける？」。
- 色で組を示さない。記録の行はすべて同じ見た目にし、対応は線だけで示す。

**焦点:** 1行目の「題名 ？」（`.hot` の枠）。

**描かない:** 人物、結合の三つの方法（この後で比べる）、注意書き。

**本文:** `books/postgresql-query-journey/09-join.md` の13〜14行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/09-join.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![本の番号だけでは、題名が分からない](/images/postgresql-query-journey/09-title-lookup.png)',
     '![最新の読了記録には本番号2・1・2しかなく、題名は画面の外の本の表で番号の行を探して付ける](/images/postgresql-query-journey/09-title-lookup.png)'),
    ('*学ぶきっかけを描く、説明用の場面。*',
     '*記録の「題名 ？」から、本の表へ伸びる1本の線を見てください。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `本の番号だけでは、題名が分からない`、`description` は `問い：記録の本番号から題名を探す`。

**コミット:** `docs(query-journey): 第9章の入口の絵で、色の組をやめて線で対応を示す`（本文：`カードの色が、本番号2の記録と本1のような逆の組を対応させていた。記録の行を同じ見た目にし、1本の線「番号で探す」で本の表とつなぐ。副題と注意書きは外した。`）

---

### Task 7: 第9章 `09-hash-join`（仕組み・手直し）

**今の問題（設計書7章）:** 本文の例（記録の本8は箱2を見る）と図の例（本4→箱1）が違う。記録も箱に入れるように読める。

**問い:** 記録の本8は、どの箱の中で照合するか。

**数値と出典:** 本文127〜133行目（番号を3で割った余りが箱の番号。記録の番号が8なら箱2を見る。箱2には2や5もある）。

**描く（2コマを縦に）:**
- 見出し：`先に分類し、同じ箱の中で照合する`（今のまま）
- 右上に札「模型」（`.model`）。
- ①「本を、番号の余りで箱へ分ける」：枠「ハッシュ表」の中に箱を3つ。箱0に値カード「3」「6」「9」、箱1に「1」「4」「7」、箱2に「2」「5」「8」。枠の見出しの右に `Buckets`（等幅）と「＝箱の数」。枠の下に「本の番号 ÷ 3 の余り＝箱の番号」。
- ②「記録の本8を照合する」：枠の外にカード「記録：本8」。そこから箱2へ細い灰色の矢印（`.ref`）、ラベル「余り2 → 箱2だけを見る」。箱2の中で「2 ×」「5 ×」「8 ✓」。箱0と箱1は破線（`.ghost`）にして「見ない」。
- 記録のカードは箱に入れない（矢印は参照の細い灰色で、記録は枠の外に置く）。

**焦点:** ②の箱2（`.hot` の太枠）。

**描かない:** 実際のハッシュ関数、`Batches` と一時ファイル（この章の後半で扱う）。

**本文:** `books/postgresql-query-journey/09-join.md` の130〜131行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/09-join.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![先に分類し、同じ箱の中で照合する](/images/postgresql-query-journey/09-hash-join.png)',
     '![本1〜9を番号の余りで三つの箱に分け、記録の本8は箱2だけを見て、2と5は一致せず8で一致する](/images/postgresql-query-journey/09-hash-join.png)'),
    ('*Hash Joinの模型。実際のハッシュ関数とは異なります。*',
     '*記録の本8は箱2だけを見て、中の2・5・8と番号を比べます（模型）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `先に分類し、同じ箱の中で照合する`、`description` は `仕組み：Hash Joinの模型（本8は箱2だけを見る）`。

**コミット:** `docs(query-journey): 第9章のハッシュ結合の図を、本文と同じ本8の例にする`（本文：`図は本4→箱1、本文は本8→箱2で例が違っていた。本文の例にそろえ、記録は箱に入れず「見る」だけにした。箱2の中で2・5・8と比べるところを焦点にした。`）

---

### Task 8: 第11章 `11-snapshots`（比較・描き直し、位置を移す）

**今の問題（設計書7章・2章）:** 3コマ共通の「見える行バージョンが違う」が、①②の内容と矛盾する。予想を求める文の直後に置いてあり、縦横比も1.54ある。

**問い:** Repeatable Read の接続Aは、Bが更新して確定した後も、どの版を読むか。

**描く（3コマを縦に、同じ配置）:**
- 見出し：`読む時点によって、見える版が変わる`（今のまま）
- 右上に札「模型」（`.model`）。
- 各コマの左にコマの名前、右にページの枠「本42の行があるページ」。A と B は小さな丸の札「A」「B」で描く（人物は描かない）。
- ①「Aが読む（Repeatable Read）」：ページの中に版のカード「版1　実験用の本 42」だけ。Aから版1へ細い灰色の矢印（`.ref`）、ラベル「見る」。
- ②「BがUPDATEしてCOMMIT」「Aがもう一度読む」（2行）：ページの中に「版1　実験用の本 42」と「版2　改訂版の本 42」が並ぶ。Bから版2へ実線の青緑（`.flow`）、ラベル「新しい版を作る」。Aの矢印は版1を指したまま。
- ③「AがCOMMITして、新しく読む」：同じ2枚。Aの矢印が版2を指す。

**焦点:** ②で A の矢印が指す版1（`.hot` の枠）。

**描かない:** xmin・xmax などの内部の値、Indexの更新、Read Committed の場合（本文で説明する）。

**本文:** `books/postgresql-query-journey/11-mvcc-and-maintenance.md` の49〜52行目。図とキャプションを、52行目の段落（「`Repeatable Read`の定義どおりなら、…必要になります。」）の直後へ移す。47行目の「次の図と見比べてください。」は変えない（移した後も、次の図はこの図を指す）。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/11-mvcc-and-maintenance.md')
text = path.read_text(encoding='utf-8')
old_block = '![読む時点によって、見える版が変わる](/images/postgresql-query-journey/11-snapshots.png)\n*本文の実験順序。Repeatable Readを明示して実行しています。*\n\n'
new_block = '![本42の行はBのUPDATEで版1と版2の二つになり、Aは②でも版1を読み、COMMIT後の③で版2を読む](/images/postgresql-query-journey/11-snapshots.png)\n*②でも、Aの矢印は版1を指したままです。AがCOMMITした後の③で、初めて版2を見ます（模型）。*\n'
anchor = '接続Aは古い題名を読み続けられません。ここで行のバージョンという考え方が必要になります。\n'
assert text.count(old_block) == 1 and text.count(anchor) == 1
text = text.replace(old_block, '')
text = text.replace(anchor, anchor + '\n' + new_block)
path.write_text(text, encoding='utf-8')
```

実行後、移した図の前後に空行が1つずつあり、47行目の段落の直後が「`Repeatable Read`の定義どおりなら、…」の段落になっていることを確かめる（`sed -n '44,62p'`）。

**catalog.json:** `title` は `読む時点によって、見える版が変わる`、`description` は `比較：Repeatable Readで見える版（3コマの模型）`。

**コミット:** `docs(query-journey): 第11章の版の図を描き直し、説明の段落の後へ移す`（本文：`3コマ共通の「見える行バージョンが違う」が①②と矛盾していた。ページの中に版1と版2が並ぶ3コマにし、②でも A の矢印が版1を指したままであることを焦点にした。予想を求める文の直後から、Repeatable Read の説明の段落の後へ移した。`）

---

### Task 9: 第11章 `11-visibility-map`（仕組み・描き直し）

**今の問題（設計書7章）:** 例の列（id・title）が、実験で作るIndex（book_id, finished_at）と違う。縦横比も1.49ある。

**問い:** Index Only Scan は、どの項目で表の行を確かめに行くか。

**描く:**
- 見出し：`×のページだけ、表を確かめに行く`（今の見出しは右端が約592で札が入らず、何を見るかも分かりにくいため、焦点に合わせて変える）
- 右上に札「模型」（`.model`）。
- 上段：Indexの枠、見出しは等幅で `(book_id, finished_at)` と「のIndex」。中にIndexの項目（部品見本の「Indexの項目」）を2つ：「42｜日時1 ▸場所」「42｜日時2 ▸場所」。
- 中段：帯「可視性マップ」。表のページごとのマスを2つ：「ページ10 ✓」「ページ11 ×」。帯の下に凡例「✓ すべて見えてよい」「× 確かめが要る」。
- 下段：表のページ（部品見本の「表のページ」）を2枚「ページ10」「ページ11」。
- 項目1（場所はページ10）：マスが✓なので、項目のそばに「表を見ずに返す」。
- 項目2（場所はページ11）：マスが×なので、ページ11の行へ細い灰色の矢印（`.ref`）、ラベル「表の行を確かめる」。矢印のそばに `Heap Fetches`（等幅）と「＝この回数」。

**焦点:** ×のマス（ページ11）の `.hot` の枠。

**描かない:** 実験の回数（0→4→0 は本文の表で扱う）、VACUUM の動き、Index の内部の段。

**本文:** `books/postgresql-query-journey/11-mvcc-and-maintenance.md` の86〜87行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/11-mvcc-and-maintenance.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![Indexだけで返せるかは、可視性にもよる](/images/postgresql-query-journey/11-visibility-map.png)',
     '![Index (book_id, finished_at) の二つの項目のうち、可視性マップが✓のページの項目は表を見ずに返し、×のページの項目だけ表の行を確かめる](/images/postgresql-query-journey/11-visibility-map.png)'),
    ('*Index Only Scanの模型。ページごとに判断します。*',
     '*×のマスと、そこから表へ伸びる矢印を見てください。この矢印の回数がHeap Fetchesです（模型）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `×のページだけ、表を確かめに行く`、`description` は `仕組み：Index Only Scanと可視性マップの模型`。

**コミット:** `docs(query-journey): 第11章の可視性マップの図を、実験の Index にそろえる`（本文：`例の列（id・title）が、実験で作る Index（book_id, finished_at）と違っていた。実験の Index の項目で描き、可視性マップが×のページの項目だけ表を確かめに行く矢印と Heap Fetches を対応させた。`）

---

### Task 10: 一覧を合わせ、全体を確かめて ship する

**Files:**
- Modify: `images/postgresql-query-journey/README.md`、`images/postgresql-query-journey/index.html`、`books/postgresql-query-journey/book-flow.html`、`books/postgresql-query-journey/FIGURE-PLAN.md`（7章の表）、`books/postgresql-query-journey/AGENTS.md`（図の枚数の行）

- [ ] **Step 1: Task 2〜9 のコミットを作業ブランチへ cherry-pick する**（コントローラーが行う。衝突したら、各タスクの置き換えを残す向きで解く）

- [ ] **Step 2: README と book-flow.html の見出しを catalog.json に合わせ、図の一覧を作り直す**

```python
import json, pathlib, re
catalog = json.loads(pathlib.Path('images/postgresql-query-journey/catalog.json').read_text(encoding='utf-8'))
titles = {item['name']: item['title'] for item in catalog}
readme = pathlib.Path('images/postgresql-query-journey/README.md')
lines = readme.read_text(encoding='utf-8').split('\n')
for i, line in enumerate(lines):
    m = re.match(r'^\| (序章|第\d+章) \| (.+?) \| \[SVG\]\(sources/([\w-]+)\.svg\) \| (.+)$', line)
    if m and m.group(3) in titles:
        lines[i] = f'| {m.group(1)} | {titles[m.group(3)]} | [SVG](sources/{m.group(3)}.svg) | {m.group(4)}'
readme.write_text('\n'.join(lines), encoding='utf-8')
flow = pathlib.Path('books/postgresql-query-journey/book-flow.html')
text = flow.read_text(encoding='utf-8')
def swap(m):
    name = m.group(2)
    return f'["{titles[name]}", "/images/postgresql-query-journey/{name}.png"]' if name in titles else m.group(0)
flow.write_text(re.sub(r'\["([^"]*)", "/images/postgresql-query-journey/([\w-]+)\.png"\]', swap, text), encoding='utf-8')
```

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（48枚）`

- [ ] **Step 3: 設計書と執筆方針の記録を更新する**

`books/postgresql-query-journey/FIGURE-PLAN.md` の7章の表で、`03-pages-and-rows`・`03-row-width`・`04-memory-regions`・`02-query-stages`・`09-title-lookup`・`09-hash-join`・`11-snapshots`・`11-visibility-map` の行の「時期」列を `試作後` から `2026-09-25 直した` にする。

`books/postgresql-query-journey/AGENTS.md` の図の枚数の行の括弧を、`（2026-09-24に第1〜2章の8枚を FIGURE-PLAN.md の型で試作し、2026-09-25に誤解を招く8枚を直した）` にする。

- [ ] **Step 4: 全体を確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window 01-explain-stages 01-scan-and-filter 01-index-to-row 05-growing-library 05-linear-scan 05-limit-search 05-limit-bands 03-pages-and-rows 03-row-width 04-memory-regions 02-query-stages 09-title-lookup 09-hash-join 11-snapshots 11-visibility-map`
Expected: `16枚中 16枚が約束を満たしています`

Run: `cd scripts/book-figures && npm test`
Expected: `ℹ pass 12`

Run: `grep -oh '/images/postgresql-query-journey/[^)]*\.png' books/postgresql-query-journey/[0-9][0-9]-*.md | sort -u | while read -r ref; do [ -f ".${ref}" ] && echo ok || echo "ない: ${ref}"; done | sort | uniq -c`
Expected: `48 ok`

Run: `git grep -n "索引" -- images/postgresql-query-journey/sources/ books/postgresql-query-journey/0[3-9]-*.md books/postgresql-query-journey/1[0-2]-*.md`
Expected: 出力なし

- [ ] **Step 5: 一覧の変更をコミットする**

```bash
git add images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html books/postgresql-query-journey/book-flow.html books/postgresql-query-journey/FIGURE-PLAN.md books/postgresql-query-journey/AGENTS.md
git commit -m "docs(query-journey): 直した8枚の見出しを一覧に合わせ、設計書の記録を更新する"
```

- [ ] **Step 6: ブランチ全体をレビューし、ship する**（ブランチ全体のレビューで出た指摘を直してから、PR を作る。試作の PR #14 がマージ済みなら main へ、未マージなら `book-query-journey-figure-pilot` へ向ける）
