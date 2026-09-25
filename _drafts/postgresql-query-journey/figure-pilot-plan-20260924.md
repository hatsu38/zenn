# 図の試作（第1〜2章）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 第1〜2章の図8枚（直し6枚＋新規2枚）を、設計書 `books/postgresql-query-journey/FIGURE-PLAN.md` の型と約束で作り直し、Zennのプレビューで確かめられる状態にする。

**Architecture:** 図は手書きのSVG（幅640）を原本にし、Playwrightで2倍解像度のPNGへ書き出す。共通の部品（`<defs>`と`<style>`）は部品見本のSVGに置き、各図へ写す。約束を満たしているかは小さなNodeスクリプトで確かめ、本文・`catalog.json`・画像のREADME・図の一覧（`index.html`）を図と同じコミットで更新する。

**Tech Stack:** SVG、Node.js 24（`node:test`）、Playwright 1.62.1（Chromium）、zenn-cli 0.5.4（プレビュー）

## Global Constraints

- 出し先はZennだけ。本文の幅はスマホで約340px、PCで約700px。
- SVGの幅は640。文字の`font-size`は22以上（見出し30、本文24、補足と札22）。
- 縦横比（高さ÷幅）は1.3以下。この計画の8枚はすべて1.3以下で描くので、Zennの幅指定は使わない。
- 画像の中に置くのは、短い見出し（15字程度まで）と「模型」「実測」の札だけ。副題と注意書きは置かない。
- 矢印：実線（青緑）＝行やデータが渡る向き、破線（茶）＝要求、細い灰色＝参照・対応、太い白抜き＝処理の段階・時間の順。矢印には動詞のラベルを付ける。
- 強調：橙の太枠（`.hot`）＝いま注目する所（1コマ1か所、比べる2枚を示すときは2枚）。灰色の破線（`.ghost`・`.skip`）＝読まない・比べない。○×✓の記号を色と併用する。
- 計画の木は、子が下、親が上、行は下から上へ。
- 本文で変えてよいのは、図の直前・直後の1〜2文、キャプション、代替テキストだけ。第1章254行目・第10章102行目・第11章136行目（設計書9章の要確認）は変えない。
- 図に入れる実測値は、本文に掲載済みのもの（2026-09-23、PostgreSQL 18.6）だけ。新しい数値を作らない。
- 代替テキストは画像内の見出しを繰り返さず、図の中の変化を文で書く。キャプションには見るところか条件を書く。
- コミットメッセージは日本語のConventional Commits（`docs(query-journey): …`、`chore(book-figures): …`）。`Co-Authored-By`は付けない。
- 作業ツリーは別セッションと共有している。ブランチを切り替える前に`git branch --show-current`と`git status`で空きを確かめる。作業ブランチは`book-query-journey-figure-pilot`。

## ファイル構成

| ファイル | 作成／変更 | 役割 |
| --- | --- | --- |
| `images/postgresql-query-journey/export.cjs` | 変更 | 図の名前やSVGのパスを渡すと、その図だけをPNGに書き出す |
| `scripts/book-figures/check-figures.cjs` | 作成 | 図が約束を満たしているかを確かめる |
| `scripts/book-figures/check-figures.test.cjs` | 作成 | 上のスクリプトの判定関数のテスト |
| `scripts/book-figures/build-index.cjs` | 作成 | `catalog.json`から図の一覧`index.html`を作る |
| `scripts/book-figures/package.json` | 変更 | `check`・`index`・`test`のスクリプトを足す |
| `images/postgresql-query-journey/parts/figure-parts.svg`と`.png` | 作成 | 部品見本（書き出し対象の`sources/`の外） |
| `images/postgresql-query-journey/sources/*.svg`と`*.png` | 変更・作成 | 試作の8枚 |
| `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html` | 変更 | 図の一覧 |
| `books/postgresql-query-journey/01-explain-basics.md`・`02-linear-search.md` | 変更 | 図の前後の文、キャプション、代替テキスト |
| `books/postgresql-query-journey/ILLUSTRATION-GUIDE.md`・`AGENTS.md` | 変更 | 約束の参照先と図の枚数 |
| `.claude/launch.json` | 変更（コミットしない） | Zennのプレビューを起動する設定 |

## 実行の分担

- Task 1はメインのセッションで実行する。途中でユーザーに関数の実装を頼む（Learn by Doing）。
- Task 2〜10はサブエージェントに任せられる。各タスクの最後で、コントローラーがPNGを見てレビューする。
- Task 11はメインのセッションで実行する。ブラウザ（Zennのプレビュー）とPRの作成を使う。

---

### Task 1: 書き出しと確認の道具を用意する

**Files:**
- Modify: `images/postgresql-query-journey/export.cjs`（全体を置き換える）
- Create: `scripts/book-figures/check-figures.cjs`
- Create: `scripts/book-figures/check-figures.test.cjs`
- Create: `scripts/book-figures/build-index.cjs`
- Modify: `scripts/book-figures/package.json`
- Modify: `images/postgresql-query-journey/catalog.json:26-61`（第1〜2章の項目を読む順に並べ替える）
- Modify: `images/postgresql-query-journey/README.md:13-18`（同じく並べ替える）
- Modify: `.claude/launch.json`（コミットしない）

**Interfaces:**
- Produces:
  - `node images/postgresql-query-journey/export.cjs [名前 | パス.svg ...]`：引数なしで`sources/`の全SVG、名前（例：`01-scan-and-filter`）で`sources/`のその図、`.svg`で終わるパス（`images/postgresql-query-journey/`からの相対）でそのSVGを、同じ場所のPNGへ書き出す。`NODE_PATH=./scripts/book-figures/node_modules`を付けてリポジトリ直下から実行する。
  - `node scripts/book-figures/check-figures.cjs 名前 ... | --all`：図ごとに✓か✗と問題の一覧を出す。問題があれば終了コード1。
  - `check-figures.cjs`のエクスポート：`findSmallFonts(svgText: string, minSize: number): number[]`、`readViewBox(svgText: string): {width: number, height: number} | null`、`findDisclaimers(svgText: string): string[]`。
  - `node scripts/book-figures/build-index.cjs`：`catalog.json`の並び順で`index.html`を書き出す。
  - Zennのプレビュー：`.claude/launch.json`の`zenn-preview`（ポート8000）。

- [ ] **Step 1: 作業ツリーとブランチを確かめる**

Run: `git branch --show-current && git status --short`
Expected: `book-query-journey-figure-pilot`と表示され、未コミットの変更がない（`_drafts/postgresql-query-journey/figure-pilot-plan-20260924.md`がコミット済みであること）。

- [ ] **Step 2: Playwrightを入れる**

Run: `cd scripts/book-figures && npm install && cd ../..`
Expected: `added N packages`。`scripts/book-figures/node_modules/playwright`ができる（`node_modules`は`scripts/book-figures/.gitignore`で除外済み）。

- [ ] **Step 3: export.cjs を、図を選んで書き出せる形に置き換える**

`images/postgresql-query-journey/export.cjs`の全体を次にする。

```js
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
```

- [ ] **Step 4: 1枚だけ書き出して、動くことを確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-search-window`
Expected: `images/postgresql-query-journey/01-search-window.png`と1行だけ表示される。

`Executable doesn't exist`と出たら、`cd scripts/book-figures && npx playwright install chromium && cd ../..`でChromiumを入れてから再実行する。

書き出したPNGは原本が変わっていないので、差分が出たら戻す：`git checkout -- images/postgresql-query-journey/01-search-window.png`

- [ ] **Step 5: 判定関数のテストを先に書く**

`scripts/book-figures/check-figures.test.cjs`を作る。

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { findSmallFonts, readViewBox, findDisclaimers } = require('./check-figures.cjs');

test('findSmallFonts：属性とスタイルの両方から、下限より小さい値を出てきた順に返す', () => {
  const svg = '<style>text{font-size:24px}.s{font-size:18px}</style><text font-size="14">a</text><text font-size="22">b</text>';
  assert.deepEqual(findSmallFonts(svg, 22), [18, 14]);
});

test('findSmallFonts：下限ちょうどの値は小さいとみなさない', () => {
  assert.deepEqual(findSmallFonts('<text font-size="22">a</text>', 22), []);
});

test('findSmallFonts：font-size がなければ空の配列を返す', () => {
  assert.deepEqual(findSmallFonts('<text>a</text>', 22), []);
});

test('readViewBox：幅と高さを数で返す', () => {
  assert.deepEqual(readViewBox('<svg viewBox="0 0 640 530">'), { width: 640, height: 530 });
});

test('findDisclaimers：断り書きの文だけを拾う', () => {
  const svg = '<text x="1">学ぶきっかけを描く絵 ／ 実測ではありません</text><text>本42</text>';
  assert.deepEqual(findDisclaimers(svg), ['学ぶきっかけを描く絵 ／ 実測ではありません']);
});
```

- [ ] **Step 6: テストが失敗することを確かめる**

Run: `node --test scripts/book-figures/check-figures.test.cjs`
Expected: FAIL。`Cannot find module './check-figures.cjs'`。

- [ ] **Step 7: 確認スクリプトを書く（findSmallFonts の中身はユーザーに頼む）**

`scripts/book-figures/check-figures.cjs`を作る。`findSmallFonts`の中身だけ`TODO(human)`にする。

```js
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
const DISCLAIMER_PATTERNS = [/ではありません/, /学ぶきっかけ/, / ／ /];

// SVGの中の font-size（属性とスタイルの両方）のうち、minSize より小さい値を、出てきた順に返す。
function findSmallFonts(svgText, minSize) {
  // TODO(human)
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
```

- [ ] **Step 8: ユーザーに findSmallFonts の実装を頼む（Learn by Doing）**

`TODO(human)`の中身（2〜6行）を、ユーザーに書いてもらう。依頼には次を含める。

- 契約：Step 5の3つのテスト（属性の`font-size="14"`とスタイルの`font-size:18px`の両方を拾う、下限ちょうどは小さくない、なければ空の配列）。
- 判断してほしい点：`px`の有無、`<style>`で定義したが使っていないクラスも数えるか、`em`など別の単位が来たらどう扱うか。
- 待つ。ユーザーが「任せる」と答えた場合だけ、次の実装を入れる。

```js
function findSmallFonts(svgText, minSize) {
  const sizes = [...svgText.matchAll(/font-size(?:="|:\s*)([\d.]+)/g)].map(match => Number(match[1]));
  return sizes.filter(size => size < minSize);
}
```

- [ ] **Step 9: テストが通ることを確かめる**

Run: `node --test scripts/book-figures/check-figures.test.cjs`
Expected: `ℹ pass 5`、`ℹ fail 0`（Node 24 の既定の表示。✔/✖ で1件ずつ見たいときは`--test-reporter=spec`を付ける）。

- [ ] **Step 10: 試作前の6枚で、確認スクリプトが問題を見つけることを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window 01-scan-and-filter 01-index-to-row 05-growing-library 05-linear-scan 05-limit-search; echo "exit=$?"`
Expected: 6枚とも✗。全図に「画像内に断り書き」（技術図4枚は副題の「 ／ 」、場面の絵2枚は注意書き）と「代替テキストが画像の見出しと同じ」が出る。場面の絵2枚（`01-search-window`・`05-growing-library`）には「文字が小さい」も出る。最後に`6枚中 0枚が約束を満たしています`と`exit=1`。

- [ ] **Step 11: 図の一覧を作るスクリプトを書く**

`scripts/book-figures/build-index.cjs`を作る。`STYLE`は今の`index.html`の`<style>`の中身と1文字も違えない。

```js
/** catalog.json の並び順で、図の一覧ページ index.html を作る。 */
const fs = require('node:fs');
const path = require('node:path');

const IMAGE_DIR = path.resolve(__dirname, '../../images/postgresql-query-journey');
const STYLE = 'body{margin:0;background:#f3f6f8;color:#243b50;font-family:system-ui,sans-serif}main{max-width:1250px;margin:auto;padding:32px}h1{font-size:28px}p{line-height:1.8}section{margin:48px 0}h2{border-bottom:2px solid #a8c8be;padding-bottom:12px}small{font-weight:400;font-size:16px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}article{background:white;border:1px solid #cedae1;border-radius:12px;padding:16px}h3{font-size:16px;min-height:48px}img{width:100%;height:auto;display:block}a{color:#176e65}article p{margin-bottom:0}@media(max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:580px){main{padding:16px}.grid{grid-template-columns:1fr}}';

function chapterName(chapter) {
  return chapter === 0 ? '序章' : `第${chapter}章`;
}

function escapeHtml(text) {
  return text.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

function article(item) {
  const title = escapeHtml(item.title);
  return `<article><h3>${title}</h3><a href="${item.name}.png"><img src="${item.name}.png" alt="${title}" loading="lazy"></a><p><a href="sources/${item.name}.svg">SVG原本</a> · <a href="${item.name}.png">PNG</a></p></article>`;
}

function main() {
  const catalog = JSON.parse(fs.readFileSync(path.join(IMAGE_DIR, 'catalog.json'), 'utf8'));
  const chapters = [...new Set(catalog.map(item => item.chapter))].sort((a, b) => a - b);
  const sections = chapters.map(chapter => {
    const items = catalog.filter(item => item.chapter === chapter);
    return `<section><h2>${chapterName(chapter)} <small>${items.length}枚</small></h2><div class="grid">${items.map(article).join('')}</div></section>`;
  }).join('');
  const html = `<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>PostgreSQL本の図解一覧</title><style>${STYLE}</style><main><h1>いつものSQLで学ぶデータ構造とアルゴリズム</h1><p>序章から第12章まで、計${catalog.length}枚。全体を見渡す絵、各章のサービスの場面、仕組みを理解する技術図を掲載しています。</p>${sections}</main></html>`;
  fs.writeFileSync(path.join(IMAGE_DIR, 'index.html'), html);
  console.log(`index.html を更新しました（${catalog.length}枚）`);
}

main();
```

- [ ] **Step 12: 今の index.html をそのまま再現できることを確かめる**

Run: `node scripts/book-figures/build-index.cjs && git diff --quiet images/postgresql-query-journey/index.html && echo "一致"`
Expected: `index.html を更新しました（46枚）`と`一致`。差分が出たら、`git diff images/postgresql-query-journey/index.html`で違う文字を探し、`STYLE`か組み立ての文字列を直す。

- [ ] **Step 13: package.json にスクリプトを足す**

`scripts/book-figures/package.json`の全体を次にする。

```json
{
  "name": "postgresql-book-figures",
  "private": true,
  "scripts": {
    "export": "node export.cjs",
    "check": "node check-figures.cjs",
    "index": "node build-index.cjs",
    "test": "node --test check-figures.test.cjs"
  },
  "devDependencies": { "playwright": "1.62.1" }
}
```

Run: `cd scripts/book-figures && npm test && cd ../..`
Expected: `ℹ pass 5`。

- [ ] **Step 14: 第1〜2章の項目を、本文で出てくる順に並べ替える**

`images/postgresql-query-journey/catalog.json`の26〜61行目（`01-index-to-row`から`05-growing-library`までの6項目）を、中身は変えずに次の順にする。

```json
  {
    "name": "01-search-window",
    "chapter": 1,
    "title": "まずは、1冊だけ探してみる",
    "description": "サービスの場面・学ぶきっかけの絵"
  },
  {
    "name": "01-scan-and-filter",
    "chapter": 1,
    "title": "結果が1行でも、調べたのは100万行",
    "description": "初期データの単純な逐次走査 ／ loops = 1"
  },
  {
    "name": "01-index-to-row",
    "chapter": 1,
    "title": "番号で場所を探し、表から行を取り出す",
    "description": "Index Scanの模型 ／ 索引の内部は第3章で扱う"
  },
  {
    "name": "05-growing-library",
    "chapter": 2,
    "title": "100万冊から、1冊見つけたら止める？",
    "description": "サービスの場面・学ぶきっかけの絵"
  },
  {
    "name": "05-linear-scan",
    "chapter": 2,
    "title": "見つけても、そこで終わりとは限らない",
    "description": "5冊へ縮めた模型 ／ 題名に一意性の指定なし"
  },
  {
    "name": "05-limit-search",
    "chapter": 2,
    "title": "LIMIT 1でも、探す量は変わる",
    "description": "読み順を固定した模型 ／ SQLの行順を保証しない"
  },
```

`images/postgresql-query-journey/README.md`の13〜18行目も同じ順にする。

```markdown
| 第1章 | まずは、1冊だけ探してみる | [SVG](sources/01-search-window.svg) | [PNG](01-search-window.png) |
| 第1章 | 結果が1行でも、調べたのは100万行 | [SVG](sources/01-scan-and-filter.svg) | [PNG](01-scan-and-filter.png) |
| 第1章 | 番号で場所を探し、表から行を取り出す | [SVG](sources/01-index-to-row.svg) | [PNG](01-index-to-row.png) |
| 第2章 | 100万冊から、1冊見つけたら止める？ | [SVG](sources/05-growing-library.svg) | [PNG](05-growing-library.png) |
| 第2章 | 見つけても、そこで終わりとは限らない | [SVG](sources/05-linear-scan.svg) | [PNG](05-linear-scan.png) |
| 第2章 | LIMIT 1でも、探す量は変わる | [SVG](sources/05-limit-search.svg) | [PNG](05-limit-search.png) |
```

Run: `node -e "JSON.parse(require('fs').readFileSync('images/postgresql-query-journey/catalog.json','utf8'))" && node scripts/book-figures/build-index.cjs`
Expected: エラーなし、`index.html を更新しました（46枚）`。`git diff --stat`で`index.html`・`catalog.json`・`README.md`に差分が出る。

- [ ] **Step 15: Zennのプレビューを起動できるようにする（コミットしない）**

`.claude/launch.json`の`configurations`の配列の末尾に、次の1項目を足す（既存の項目は消さない）。

```json
    {
      "name": "zenn-preview",
      "runtimeExecutable": "npx",
      "runtimeArgs": ["-y", "-p", "zenn-cli@0.5.4", "zenn", "preview", "--port", "8000"],
      "port": 8000
    }
```

`preview_start`で`zenn-preview`を起動し、`http://localhost:8000/books/postgresql-query-journey/01-explain-basics%252Emd`を開く（章のURLは`.md`を二重にエンコードした`%252Emd`で終わる）。ポート8000で、このリポジトリの`zenn preview`がすでに動いている場合（`ps`で`zenn preview`、作業ディレクトリがリポジトリ直下）は、起動せずに`navigate`でそのURLを開く。
Expected: 第1章が表示され、`read_console_messages`にエラーがない。確かめたら`preview_stop`で止める。`.claude/launch.json`はgitの管理外なので、`git status`に出ないことも確かめる。

- [ ] **Step 16: コミットする**

```bash
git add images/postgresql-query-journey/export.cjs scripts/book-figures/check-figures.cjs scripts/book-figures/check-figures.test.cjs scripts/book-figures/build-index.cjs scripts/book-figures/package.json images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "chore(book-figures): 図を選んで書き出し、約束を確かめる道具を足す" -m "図を1枚ずつ直すときに、変えていないPNGまで書き出し直さないよう、export.cjs に図の名前を渡せるようにする。設計書4章の約束（文字の大きさ、縦横比、画像内の断り書き、キャプションと代替テキスト）を確かめる check-figures.cjs と、catalog.json から図の一覧を作る build-index.cjs を足す。第1〜2章の項目は本文で出てくる順に並べ替えた。"
```

---

### Task 2: 部品見本を作り、約束の参照先を書く

**Files:**
- Create: `images/postgresql-query-journey/parts/figure-parts.svg`
- Create: `images/postgresql-query-journey/parts/figure-parts.png`（書き出し）
- Modify: `books/postgresql-query-journey/ILLUSTRATION-GUIDE.md`（末尾に節を足す）
- Modify: `images/postgresql-query-journey/README.md`（「編集する」「PNGを再出力する」に追記し、節を2つ足す）

**Interfaces:**
- Consumes: Task 1の`export.cjs`（`.svg`のパスを渡す書き方）。
- Produces: 部品見本の`<defs>`と`<style>`。Task 3〜10の図はこれと同じものを使う（各タスクのSVGに全文を載せてある）。

- [ ] **Step 1: 部品見本のSVGを書く**

`images/postgresql-query-journey/parts/figure-parts.svg`を作る。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="950" viewBox="0 0 640 950" role="img" aria-labelledby="title">
  <title id="title">図の部品見本</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="950" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">図の部品見本</text>
  <g id="row-card">
    <text x="24" y="124" class="s b">行カード</text>
    <rect x="220" y="100" width="240" height="36" rx="4" class="row"/>
    <text x="234" y="125" class="s">42　実験用の本 42</text>
  </g>
  <g id="match-card">
    <text x="24" y="176" class="s b">一致した行</text>
    <rect x="220" y="152" width="240" height="36" rx="4" class="match"/>
    <text x="234" y="177" class="s">42　実験用の本 42</text>
  </g>
  <g id="table-page">
    <text x="24" y="232" class="s b">表のページ</text>
    <rect x="220" y="204" width="396" height="92" rx="10" class="page"/>
    <text x="236" y="230" class="s b">ページ 0</text>
    <rect x="236" y="244" width="170" height="34" rx="4" class="row"/>
    <text x="248" y="268" class="s">1　本1</text>
    <rect x="418" y="244" width="170" height="34" rx="4" class="row"/>
    <text x="430" y="268" class="s">2　本2</text>
  </g>
  <g id="index-entry">
    <text x="24" y="350" class="s b">Indexの項目</text>
    <rect x="220" y="314" width="396" height="60" rx="10" class="ipage"/>
    <rect x="236" y="326" width="52" height="36" rx="4" class="row"/>
    <text x="262" y="351" text-anchor="middle" class="s">42</text>
    <text x="300" y="351" class="s m">▸ 場所</text>
  </g>
  <g id="plan-node">
    <text x="24" y="424" class="s b">計画のノード</text>
    <rect x="220" y="394" width="396" height="48" rx="12" class="node"/>
    <text x="236" y="426" class="mono b">Seq Scan on books</text>
  </g>
  <g id="quantity-band">
    <text x="24" y="488" class="s b">量の帯</text>
    <rect x="220" y="464" width="300" height="32" rx="4" class="band"/>
    <rect x="520" y="464" width="96" height="32" rx="4" class="skip"/>
    <text x="220" y="524" class="m">灰色＝比べた行、破線＝比べなかった行</text>
  </g>
  <g id="emphasis">
    <text x="24" y="572" class="s b">焦点</text>
    <rect x="220" y="548" width="160" height="36" rx="6" class="hot"/>
    <text x="300" y="573" text-anchor="middle" class="s b">注目する所</text>
    <text x="400" y="572" class="s b">比べない</text>
    <rect x="496" y="548" width="120" height="36" rx="6" class="ghost"/>
    <text x="556" y="573" text-anchor="middle" class="m">本3</text>
  </g>
  <g id="arrows">
    <text x="24" y="630" class="s b">行・データの流れ</text>
    <path d="M260 624 H420" class="flow"/>
    <text x="24" y="680" class="s b">要求</text>
    <path d="M260 674 H420" class="req"/>
    <text x="24" y="730" class="s b">参照・対応</text>
    <path d="M260 724 H420" class="ref"/>
    <text x="24" y="780" class="s b">処理の段階・時間の順</text>
    <path d="M260 756 H400 V746 L436 772 L400 798 V788 H260 Z" class="step"/>
  </g>
  <g id="tags">
    <text x="24" y="850" class="s b">札</text>
    <rect x="220" y="826" width="130" height="36" rx="18" class="real"/>
    <text x="285" y="851" text-anchor="middle" class="tag">実測</text>
    <rect x="370" y="826" width="130" height="36" rx="18" class="model"/>
    <text x="435" y="851" text-anchor="middle" class="tag">模型</text>
  </g>
  <g id="marks">
    <text x="24" y="910" class="s b">記号</text>
    <text x="220" y="910" class="b teal">○ 一致</text>
    <text x="340" y="910" class="b">× 除外</text>
    <text x="460" y="910" class="b teal">✓ 条件に合う</text>
  </g>
</svg>
```

- [ ] **Step 2: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs parts/figure-parts.svg`
Expected: `images/postgresql-query-journey/parts/figure-parts.png`と表示される。

ReadツールでPNGを開き、次を確かめる：どの文字も枠からはみ出していない。矢印の4種類が見分けられる（実線の先が塗りの三角、破線の先が線の三角、灰色の細線、白抜きの太い矢印）。「実測」と「模型」の札の色が違う。はみ出していたら、その要素の`x`・`width`を直して書き出し直す。

- [ ] **Step 3: ILLUSTRATION-GUIDE.md の末尾に節を足す**

`books/postgresql-query-journey/ILLUSTRATION-GUIDE.md`の末尾（最後の段落の後ろに空行を1つ置いて）に次を足す。

```markdown
## 2026年9月24日：見るところが分かる図へ

図の型（問い・仕組み・観察・比較）と、部品・矢印・強調・文字・大きさの約束は、[FIGURE-PLAN.md](FIGURE-PLAN.md)の3〜4章に従う。部品の見本は[figure-parts.svg](../../images/postgresql-query-journey/parts/figure-parts.svg)。新しく描く図と描き直す図は、見本の`<defs>`と`<style>`をそのまま写して使う。約束を満たしているかは`node scripts/book-figures/check-figures.cjs 図の名前`で確かめる。第1〜2章の8枚を、この型で試作した。
```

- [ ] **Step 4: 画像のREADMEに、道具の使い方を書く**

`images/postgresql-query-journey/README.md`の「## 編集する」節の最後の段落（`図の設計意図・用語と模型の対応は …`）の後ろに、空行を置いて次の段落を足す。

```markdown
新しく描く図と描き直す図は、[部品見本](parts/figure-parts.svg)の`<defs>`と`<style>`を写して使います。行カード・ページ枠・索引の項目・計画のノード・量の帯・矢印・札の見た目がそろいます。見本の見た目は[PNG](parts/figure-parts.png)で確認できます。
```

同じファイルの「## PNGを再出力する」節で、`` `sources/`内のSVGをすべてChromiumで描画し、…元のSVGは変更しません。`` の段落の後ろに、空行を置いて次を足す。

````markdown
図の名前を渡すと、その図だけを書き出します。変更していない図のPNGに差分を出さないため、ふだんはこちらを使います。

```sh
NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-scan-and-filter 05-limit-bands
```

`.svg`で終わるパスを渡すと、そのSVGを同じ場所のPNGへ書き出します（例：`parts/figure-parts.svg`）。Playwrightは`scripts/book-figures`で`npm install`して入れます。
````

同じファイルの「## 本文に掲載する」の見出しの直前に、次の2節を足す。

````markdown
## 約束を確かめる

図が[設計書](../../books/postgresql-query-journey/FIGURE-PLAN.md)4章の約束を満たしているかを確かめます。見るのは、文字の大きさ、縦横比、画像内の断り書き、PNGの書き出し、catalog.jsonへの登録、本文からの参照とキャプション・代替テキストです。

```sh
node scripts/book-figures/check-figures.cjs 01-scan-and-filter
```

`--all`を付けると全部の図を確かめます。描き直す前の図は約束を満たしていないので、`--all`では多くの図が✗になります。

## 図の一覧を作り直す

[図の一覧](index.html)は`catalog.json`から作ります。図を足したり見出しを変えたりしたら、次を実行します。

```sh
node scripts/book-figures/build-index.cjs
```

````

- [ ] **Step 5: コミットする**

```bash
git add images/postgresql-query-journey/parts/ books/postgresql-query-journey/ILLUSTRATION-GUIDE.md images/postgresql-query-journey/README.md
git commit -m "docs(query-journey): 図の部品見本と約束の参照先を追加" -m "描き直す図の見た目をそろえるため、行カード・ページ枠・索引の項目・計画のノード・量の帯・矢印・札をまとめた部品見本を作る。ILLUSTRATION-GUIDE と画像の README から、設計書の約束と道具の使い方を参照できるようにした。"
```

---

### Task 3: 第1章 `01-scan-and-filter`（観察・描き直し）

観察の型の基準にする図。問いは「1行を返すまでに、何行を比べたか」。

**Files:**
- Modify: `images/postgresql-query-journey/sources/01-scan-and-filter.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/01-scan-and-filter.png`（書き出し）
- Modify: `books/postgresql-query-journey/01-explain-basics.md:249-252`
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 1の`export.cjs`・`check-figures.cjs`・`build-index.cjs`。
- Produces: 量の帯（`.band`）と実測の札の描き方の基準。Task 4がこれに合わせる。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-scan-and-filter`
Expected: `✗ 01-scan-and-filter`。「画像内に断り書き」と「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/01-scan-and-filter.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="500" viewBox="0 0 640 500" role="img" aria-labelledby="title">
  <title id="title">1行のために、100万行を比べた</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="500" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">1行のために、100万行を比べた</text>
  <rect x="486" y="22" width="130" height="36" rx="18" class="real"/>
  <text x="551" y="47" text-anchor="middle" class="tag">件数は実測</text>
  <g id="node">
    <rect x="24" y="76" width="592" height="92" rx="12" class="node"/>
    <text x="44" y="112" class="mono b">Seq Scan on books</text>
    <text x="596" y="112" text-anchor="end" class="mono m">loops=1</text>
    <text x="44" y="148" class="mono">Filter: (title = '実験用の本 42'::text)</text>
  </g>
  <g id="scan">
    <path d="M24 190 H576 V180 L616 206 L576 232 V222 H24 Z" class="step"/>
    <text x="40" y="214" class="s">先頭から最後まで、1行ずつ題名を比べる</text>
  </g>
  <g id="band">
    <rect x="24" y="250" width="592" height="56" rx="6" class="band"/>
    <text x="44" y="286" class="b">× 除外 999,999行</text>
    <text x="24" y="332" class="m">先頭</text>
    <text x="84" y="332" class="mono m">▲ Rows Removed by Filter: 999999</text>
    <text x="616" y="332" text-anchor="end" class="m">最後</text>
  </g>
  <g id="match">
    <path d="M24 350 Q24 364 40 364 H304 Q320 364 320 384 Q320 364 336 364 H600 Q616 364 616 350" fill="none" stroke="#243b50" stroke-width="2"/>
    <text x="24" y="420" class="m">1行の幅は</text>
    <text x="24" y="450" class="m">帯の100万分の1</text>
    <rect x="206" y="396" width="228" height="70" rx="10" class="hot"/>
    <text x="320" y="426" text-anchor="middle" class="b">○ 一致 1行</text>
    <text x="320" y="454" text-anchor="middle" class="mono">rows=1.00</text>
    <path d="M434 431 H494" class="flow"/>
    <text x="464" y="404" text-anchor="middle" class="s teal">返す</text>
    <rect x="500" y="403" width="116" height="56" rx="10" class="panel"/>
    <text x="558" y="439" text-anchor="middle" class="b">結果</text>
  </g>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-scan-and-filter`
Expected: `images/postgresql-query-journey/01-scan-and-filter.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 見出し「1行のために、100万行を比べた」が「件数は実測」の札に重なっていない。
- 灰色の帯が横いっぱいに伸び、その下の括弧から橙の枠「○ 一致 1行 / rows=1.00」が1つだけ出ている（焦点は1か所）。
- `Filter: (title = '実験用の本 42')`と`▲ Rows Removed by Filter: 999999`が枠や隣の文字にかぶっていない。
- 値が本文の出力（`01-explain-basics.md`の`Rows Removed by Filter: 999999`、`rows=1.00`、`loops=1`）と一致している。

はみ出しや重なりがあれば、その要素の`x`・`y`・`width`を直して書き出し直す。

- [ ] **Step 4: 本文の前の文・代替テキスト・キャプションを直す**

`books/postgresql-query-journey/01-explain-basics.md`で、次の4行を置き換える。

置き換え元：

```markdown
次は、この初期データを単純な1回の逐次走査で読んだ場合の行数の説明図です。時間の実測結果ではありません。

![結果が1行でも、調べたのは100万行](/images/postgresql-query-journey/01-scan-and-filter.png)
*初期データの単純な逐次走査（loops = 1）。帯は行の集まりを表し、本数は省略しています。*
```

置き換え先：

```markdown
帯の長さで、除外した行と返した1行の差を見てください。

![100万行の帯を先頭から最後まで比べ、999,999行を除外して1行だけを返す](/images/postgresql-query-journey/01-scan-and-filter.png)
*件数は2026年9月23日の実測。帯の長さは行数に比例させ、1行のカードだけを拡大しています。*
```

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "title": "結果が1行でも、調べたのは100万行",
    "description": "初期データの単純な逐次走査 ／ loops = 1"
```

置き換え先：

```json
    "title": "1行のために、100万行を比べた",
    "description": "観察：Seq Scanの実測を帯で見る"
```

`images/postgresql-query-journey/README.md`で置き換える。

置き換え元：`| 第1章 | 結果が1行でも、調べたのは100万行 | [SVG](sources/01-scan-and-filter.svg) | [PNG](01-scan-and-filter.png) |`

置き換え先：`| 第1章 | 1行のために、100万行を比べた | [SVG](sources/01-scan-and-filter.svg) | [PNG](01-scan-and-filter.png) |`

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（46枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-scan-and-filter`
Expected: `✓ 01-scan-and-filter`、`1枚中 1枚が約束を満たしています`。

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/01-scan-and-filter.svg images/postgresql-query-journey/01-scan-and-filter.png books/postgresql-query-journey/01-explain-basics.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第1章の走査の図を、実測の帯で描き直す" -m "1行と999,999行が同じ大きさの箱で描かれ、量の差も出力との対応も見えなかった。100万行を灰色の帯にし、Rows Removed by Filter と rows=1.00 を図の中に書き込んで、帯から1行だけが出る形にした。一致した行の位置は第2章の答えになるので描いていない。"
```

---

### Task 4: 第2章 新規 `05-limit-bands`（観察・新規）

問いは「目的の本の位置で、比べる行数はどれだけ変わったか」。結果の表（`02-linear-search.md`の195〜200行目）の直後に置く。

**Files:**
- Create: `images/postgresql-query-journey/sources/05-limit-bands.svg`
- Create: `images/postgresql-query-journey/05-limit-bands.png`（書き出し）
- Modify: `books/postgresql-query-journey/02-linear-search.md:200-202`（図を挿入）
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 3の量の帯の描き方（`.band`・`.skip`・実測の札）。
- Produces: 本文から参照される`05-limit-bands.png`。

- [ ] **Step 1: まだ図がないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-limit-bands`
Expected: `✗ 05-limit-bands`、`SVG がない: images/postgresql-query-journey/sources/05-limit-bands.svg`。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/05-limit-bands.svg`を作る。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="550" viewBox="0 0 640 550" role="img" aria-labelledby="title">
  <title id="title">位置で変わる、比べる行数</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="550" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">位置で変わる、比べる行数</text>
  <rect x="396" y="22" width="220" height="36" rx="18" class="real"/>
  <text x="506" y="47" text-anchor="middle" class="tag">実測 2026-09-23</text>
  <text x="200" y="98" class="m">先頭</text>
  <text x="616" y="98" text-anchor="end" class="m">最後</text>
  <g id="row-1">
    <text x="24" y="134" class="s b">本42</text>
    <text x="24" y="162" class="mono">LIMITなし</text>
    <rect x="200" y="112" width="416" height="36" rx="4" class="band"/>
    <circle cx="208" cy="130" r="7" fill="#fff" stroke="#176e65" stroke-width="3"/>
    <text x="616" y="178" text-anchor="end" class="s b">1,000,000行</text>
  </g>
  <g id="row-2">
    <text x="24" y="224" class="s b">本42</text>
    <text x="24" y="252" class="mono">LIMIT 1</text>
    <rect x="200" y="202" width="416" height="36" rx="4" class="skip"/>
    <rect x="192" y="192" width="36" height="56" rx="10" class="hot"/>
    <rect x="200" y="202" width="4" height="36" class="band"/>
    <circle cx="208" cy="220" r="7" fill="#fff" stroke="#176e65" stroke-width="3"/>
    <path d="M218 194 V246" stroke="#243b50" stroke-width="3"/>
    <text x="240" y="228" class="s b">ここで止まった（帯のほぼ0%）</text>
    <text x="616" y="268" text-anchor="end" class="s b">42行</text>
  </g>
  <g id="row-3">
    <text x="24" y="314" class="s b">本999999</text>
    <text x="24" y="342" class="mono">LIMIT 1</text>
    <rect x="200" y="292" width="416" height="36" rx="4" class="band"/>
    <circle cx="604" cy="310" r="7" fill="#fff" stroke="#176e65" stroke-width="3"/>
    <path d="M614 284 V336" stroke="#243b50" stroke-width="3"/>
    <text x="616" y="358" text-anchor="end" class="s b">999,999行（最後の1行は比べない）</text>
  </g>
  <g id="row-4">
    <text x="24" y="404" class="s b">存在しない本</text>
    <text x="24" y="432" class="mono">LIMIT 1</text>
    <rect x="200" y="382" width="416" height="36" rx="4" class="band"/>
    <text x="616" y="448" text-anchor="end" class="s b">1,000,000行（一致なし）</text>
  </g>
  <g id="legend">
    <rect x="24" y="478" width="40" height="20" class="band"/>
    <text x="72" y="496" class="m">比べた行</text>
    <rect x="224" y="478" width="40" height="20" class="skip"/>
    <text x="272" y="496" class="m">比べなかった行</text>
    <circle cx="44" cy="522" r="7" fill="#fff" stroke="#176e65" stroke-width="3"/>
    <text x="72" y="530" class="m">一致した行</text>
    <path d="M244 510 V534" stroke="#243b50" stroke-width="3"/>
    <text x="272" y="530" class="m">止まった位置</text>
  </g>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 05-limit-bands`
Expected: `images/postgresql-query-journey/05-limit-bands.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 4本の帯が同じ長さで、2本目だけが破線（比べなかった）で、橙の枠「ここで止まった（帯のほぼ0%）」が1か所だけある。
- 右端の行数が本文の表（`02-linear-search.md`の197〜200行目：1,000,000／42／999,999／1,000,000）と一致している。
- 見出しと「実測 2026-09-23」の札が重なっていない。左の「本999999」「存在しない本」が帯にかぶっていない。
- 凡例の4項目が2行に収まっている。

はみ出しがあれば座標を直して書き出し直す。

- [ ] **Step 4: 本文に図を入れる**

`books/postgresql-query-journey/02-linear-search.md`で置き換える。

置き換え元：

```markdown
| 存在しない本・LIMIT 1 | 0 | 1,000,000 | 1,000,000 |

目的の行が後ろにあれば、そこまで調べます。
```

置き換え先：

```markdown
| 存在しない本・LIMIT 1 | 0 | 1,000,000 | 1,000,000 |

4本の帯で、灰色の長さ（比べた行数）を比べてください。

![同じ長さの帯が4本。本42のLIMITなしと存在しない本は100万行すべて、本999999は999,999行を比べ、本42のLIMIT 1だけが42行で止まる](/images/postgresql-query-journey/05-limit-bands.png)
*表の4つの実測を帯にしたもの。この章の設定で、毎回表の先頭から読んでいます。*

目的の行が後ろにあれば、そこまで調べます。
```

- [ ] **Step 5: 図の一覧に足す**

`images/postgresql-query-journey/catalog.json`で置き換える（第3章の最初の項目の直前に足す）。

置き換え元：

```json
  {
    "name": "06-btree-path",
```

置き換え先：

```json
  {
    "name": "05-limit-bands",
    "chapter": 2,
    "title": "位置で変わる、比べる行数",
    "description": "観察：4つの実測を帯で比べる"
  },
  {
    "name": "06-btree-path",
```

`images/postgresql-query-journey/README.md`で、`| 第3章 | 8を探す：範囲を選んでから、値を探す |`で始まる行の直前に、次の行を足す。

```markdown
| 第2章 | 位置で変わる、比べる行数 | [SVG](sources/05-limit-bands.svg) | [PNG](05-limit-bands.png) |
```

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（47枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-limit-bands`
Expected: `✓ 05-limit-bands`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/05-limit-bands.svg images/postgresql-query-journey/05-limit-bands.png books/postgresql-query-journey/02-linear-search.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第2章に、LIMITの実測を帯で比べる図を追加" -m "章の結論は、目的の本の位置で比べる行数が変わることだが、結果の表の数字を読み比べるしかなかった。同じ長さの帯4本に比べた範囲と止まった位置を描き、42行だけが極端に短いことを見て分かるようにした。値は本文の表の実測（2026-09-23）だけを使っている。"
```

**任意のチェックポイント：** Task 3と4で観察の型が2枚そろう。ユーザーにPNGを見せて、帯の描き方の方向を確かめてから先へ進んでもよい。

---

### Task 5: 第2章 `05-limit-search`（仕組み・描き直し）

問いは「LIMIT 1は、どうやって走査を止めるのか」。今の図の②③（後ろで見つかる・ない）は、次の節の実験の答えなので外す。

**Files:**
- Modify: `images/postgresql-query-journey/sources/05-limit-search.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/05-limit-search.png`（書き出し）
- Modify: `books/postgresql-query-journey/02-linear-search.md:142-143`
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 2の部品（`.node`・`.req`・`.flow`・`.ghost`）。
- Produces: 計画のノードと「要求・行」の矢印の描き方。第6章`02-execution-tree`の描き直しで同じものを使う。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-limit-search`
Expected: `✗ 05-limit-search`。「画像内に断り書き」（副題の「 ／ 」）と「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/05-limit-search.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="570" viewBox="0 0 640 570" role="img" aria-labelledby="title">
  <title id="title">Limitが次の行を求めなくなる</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="570" fill="#f5f7f9"/>
  <text x="24" y="48" class="h"><tspan font-family="ui-monospace,Menlo,monospace">Limit</tspan>が次の行を求めなくなる</text>
  <rect x="540" y="22" width="76" height="36" rx="18" class="model"/>
  <text x="578" y="47" text-anchor="middle" class="tag">模型</text>
  <g id="limit">
    <rect x="180" y="72" width="280" height="64" rx="12" class="node"/>
    <text x="320" y="112" text-anchor="middle" class="b"><tspan font-family="ui-monospace,Menlo,monospace">Limit</tspan>（1行まで）</text>
  </g>
  <g id="messages">
    <path d="M300 140 V228" class="req"/>
    <text x="312" y="164" class="s brown">① 求める</text>
    <path d="M208 282 V146" class="flow"/>
    <text x="40" y="204" class="s b teal">② 行を渡す</text>
    <path d="M420 140 V228" class="req"/>
    <path d="M404 178 L436 210 M436 178 L404 210" stroke="#b88020" stroke-width="5" stroke-linecap="round"/>
    <text x="446" y="202" class="s b brown">③ もう求めない</text>
  </g>
  <g id="seqscan">
    <rect x="24" y="236" width="592" height="200" rx="12" class="node"/>
    <text x="596" y="268" text-anchor="end" class="mono b">Seq Scan on books</text>
    <rect x="44" y="286" width="100" height="70" rx="8" class="row"/>
    <text x="94" y="314" text-anchor="middle" class="b">本1</text>
    <text x="94" y="342" text-anchor="middle">海</text>
    <rect x="158" y="286" width="100" height="70" rx="8" class="match"/>
    <text x="208" y="314" text-anchor="middle" class="b">本2</text>
    <text x="208" y="342" text-anchor="middle">星</text>
    <rect x="272" y="286" width="100" height="70" rx="8" class="ghost"/>
    <text x="322" y="314" text-anchor="middle" class="m">本3</text>
    <text x="322" y="342" text-anchor="middle" class="m">森</text>
    <rect x="386" y="286" width="100" height="70" rx="8" class="ghost"/>
    <text x="436" y="314" text-anchor="middle" class="m">本4</text>
    <text x="436" y="342" text-anchor="middle" class="m">空</text>
    <rect x="500" y="286" width="100" height="70" rx="8" class="ghost"/>
    <text x="550" y="314" text-anchor="middle" class="m">本5</text>
    <text x="550" y="342" text-anchor="middle" class="m">山</text>
    <text x="94" y="396" text-anchor="middle" class="b">×</text>
    <text x="208" y="396" text-anchor="middle" class="b teal">○</text>
    <text x="436" y="396" text-anchor="middle" class="m">比べない</text>
  </g>
  <g id="numbers">
    <text x="24" y="474" class="s">模型：×1＋○1＝2枚で終わり</text>
    <rect x="24" y="492" width="72" height="34" rx="17" class="real"/>
    <text x="60" y="516" text-anchor="middle" class="tag">実測</text>
    <text x="108" y="516" class="mono">Rows Removed by Filter: 41</text>
    <text x="108" y="550" class="s">＋ <tspan class="mono">rows=1.00</tspan> ＝ 42行</text>
  </g>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 05-limit-search`
Expected: `images/postgresql-query-journey/05-limit-search.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 上に`Limit`、下に`Seq Scan on books`があり、①（破線・下向き）、②（実線・上向き）、③（破線に橙の×）の3本の矢印が重ならずに読める。焦点は③の×だけ。
- `Seq Scan on books`の文字が②の矢印に重なっていない。
- 本3〜5が破線の枠で、「比べない」と書かれている。「未読」という語がない。
- 実測の値が本文の出力（`Rows Removed by Filter: 41`、`rows=1.00`、合計42行）と一致している。

- [ ] **Step 4: 代替テキストとキャプションを直す**

`books/postgresql-query-journey/02-linear-search.md`で置き換える。

置き換え元：

```markdown
![LIMIT 1でも、探す量は変わる](/images/postgresql-query-journey/05-limit-search.png)
*読み順を固定した模型。SQLの行順は保証されません。*
```

置き換え先：

```markdown
![Seq Scanが2冊目で一致した行をLimitへ渡すと、Limitは次の行を求めなくなり、3冊目から後は比べない](/images/postgresql-query-journey/05-limit-search.png)
*Limitが次の行を求めなくなった時点で、Seq Scanも止まります（模型）。*
```

直後の145行目「これは早く見つかった場合の模型です。遅く見つかる場合と見つからない場合は、次で実際に確かめます。」はそのまま残す。

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "title": "LIMIT 1でも、探す量は変わる",
    "description": "読み順を固定した模型 ／ SQLの行順を保証しない"
```

置き換え先：

```json
    "title": "Limitが次の行を求めなくなる",
    "description": "仕組み：LIMIT 1の模型"
```

`images/postgresql-query-journey/README.md`で置き換える。

置き換え元：`| 第2章 | LIMIT 1でも、探す量は変わる | [SVG](sources/05-limit-search.svg) | [PNG](05-limit-search.png) |`

置き換え先：`| 第2章 | Limitが次の行を求めなくなる | [SVG](sources/05-limit-search.svg) | [PNG](05-limit-search.png) |`

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（47枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-limit-search`
Expected: `✓ 05-limit-search`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/05-limit-search.svg images/postgresql-query-journey/05-limit-search.png books/postgresql-query-journey/02-linear-search.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第2章のLIMITの図を、要求が止まる仕組みの図に描き直す" -m "今の図は、次の節で確かめる「遅く見つかる」「見つからない」の答えを先に描いていた。早く見つかる場合だけにし、LimitがSeq Scanに次の行を求めなくなる様子を、要求（破線）と行（実線）の矢印で描いた。同じページの行は読み込まれているので、「未読」を「比べない」に改めた。"
```

---

### Task 6: 第2章 `05-linear-scan`（仕組み・手直し）

問いは「LIMITなしで探すと、何回比べるか」。一致を本2に移し、`05-limit-search`と同じ本にそろえる。

**Files:**
- Modify: `images/postgresql-query-journey/sources/05-linear-scan.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/05-linear-scan.png`（書き出し）
- Modify: `books/postgresql-query-journey/02-linear-search.md:89-92`
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 2の部品。Task 5と同じ5冊（本1 海／本2 星／本3 森／本4 空／本5 山）。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-linear-scan`
Expected: `✗ 05-linear-scan`。「画像内に断り書き」と「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/05-linear-scan.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="510" viewBox="0 0 640 510" role="img" aria-labelledby="title">
  <title id="title">一致した後も、最後まで比べる</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="510" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">一致した後も、最後まで比べる</text>
  <rect x="540" y="22" width="76" height="36" rx="18" class="model"/>
  <text x="578" y="47" text-anchor="middle" class="tag">模型</text>
  <rect x="24" y="74" width="196" height="42" rx="21" fill="#fff" stroke="#243b50" stroke-width="2"/>
  <text x="122" y="102" text-anchor="middle" class="s">探す題名：星</text>
  <text x="266" y="146" class="s b">一致した後も比べる</text>
  <rect x="258" y="156" width="366" height="160" rx="12" fill="none" stroke="#b88020" stroke-width="4"/>
  <g id="cards">
    <rect x="24" y="166" width="108" height="76" rx="8" class="row"/>
    <text x="78" y="198" text-anchor="middle" class="b">本1</text>
    <text x="78" y="228" text-anchor="middle">海</text>
    <rect x="145" y="166" width="108" height="76" rx="8" class="match"/>
    <text x="199" y="198" text-anchor="middle" class="b">本2</text>
    <text x="199" y="228" text-anchor="middle">星</text>
    <rect x="266" y="166" width="108" height="76" rx="8" class="row"/>
    <text x="320" y="198" text-anchor="middle" class="b">本3</text>
    <text x="320" y="228" text-anchor="middle">森</text>
    <rect x="387" y="166" width="108" height="76" rx="8" class="row"/>
    <text x="441" y="198" text-anchor="middle" class="b">本4</text>
    <text x="441" y="228" text-anchor="middle">空</text>
    <rect x="508" y="166" width="108" height="76" rx="8" class="row"/>
    <text x="562" y="198" text-anchor="middle" class="b">本5</text>
    <text x="562" y="228" text-anchor="middle">山</text>
  </g>
  <g id="marks">
    <text x="78" y="272" text-anchor="middle" class="s">①</text>
    <text x="199" y="272" text-anchor="middle" class="s">②</text>
    <text x="320" y="272" text-anchor="middle" class="s">③</text>
    <text x="441" y="272" text-anchor="middle" class="s">④</text>
    <text x="562" y="272" text-anchor="middle" class="s">⑤</text>
    <text x="78" y="302" text-anchor="middle" class="b">×</text>
    <text x="199" y="302" text-anchor="middle" class="b teal">○</text>
    <text x="320" y="302" text-anchor="middle" class="b">×</text>
    <text x="441" y="302" text-anchor="middle" class="b">×</text>
    <text x="562" y="302" text-anchor="middle" class="b">×</text>
  </g>
  <rect x="24" y="334" width="592" height="56" rx="10" class="panel"/>
  <text x="320" y="370" text-anchor="middle" class="b">比べた5枚＝×4（除外）＋○1（返す）</text>
  <rect x="24" y="408" width="72" height="34" rx="17" class="real"/>
  <text x="60" y="432" text-anchor="middle" class="tag">実測</text>
  <text x="108" y="432" class="s">100万冊では：除外 999,999＋返した 1</text>
  <text x="24" y="482" class="m">5冊なら5回、100万冊なら100万回比べる</text>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 05-linear-scan`
Expected: `images/postgresql-query-journey/05-linear-scan.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 橙の枠が本3〜5と③〜⑤の×を囲み、その上に「一致した後も比べる」がある（焦点は1か所）。枠の右端が画像からはみ出していない。
- 本2だけ太い緑の枠で、下に○がある。
- 「同じ題名かもしれないので確認」や「一意性」という語がない。
- 実測の値「除外 999,999＋返した 1」が本文の出力と一致している。

- [ ] **Step 4: 前の文・代替テキスト・キャプションを直す**

`books/postgresql-query-journey/02-linear-search.md`で2か所置き換える。

1か所目。置き換え元：`5冊の模型で考えます。本4を見つけても、`

置き換え先：`5冊の模型で考えます。本2を見つけても、`

（同じ文の残り「同じ題名の本が後ろにあるかもしれません。…」は設計書9章の要確認1に関わるので変えない。）

2か所目。置き換え元：

```markdown
![見つけても、そこで終わりとは限らない](/images/postgresql-query-journey/05-linear-scan.png)
*5冊へ縮めた模型。題名に一意性の指定はありません。*
```

置き換え先：

```markdown
![5冊を先頭から順に比べ、2冊目の星が一致した後も3冊目から5冊目まで比べる。比べたのは5冊で、除外4冊と返した1冊](/images/postgresql-query-journey/05-linear-scan.png)
*5冊へ縮めた模型。条件に合う行をすべて返す検索なので、一致した後も最後まで比べます。*
```

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "title": "見つけても、そこで終わりとは限らない",
    "description": "5冊へ縮めた模型 ／ 題名に一意性の指定なし"
```

置き換え先：

```json
    "title": "一致した後も、最後まで比べる",
    "description": "仕組み：5冊の模型（LIMITなし）"
```

`images/postgresql-query-journey/README.md`で置き換える。

置き換え元：`| 第2章 | 見つけても、そこで終わりとは限らない | [SVG](sources/05-linear-scan.svg) | [PNG](05-linear-scan.png) |`

置き換え先：`| 第2章 | 一致した後も、最後まで比べる | [SVG](sources/05-linear-scan.svg) | [PNG](05-linear-scan.png) |`

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（47枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-linear-scan`
Expected: `✓ 05-linear-scan`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/05-linear-scan.svg images/postgresql-query-journey/05-linear-scan.png books/postgresql-query-journey/02-linear-search.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第2章の線形探索の図に、比べた順番と実測との対応を描く" -m "比べる回数が図の印として描かれず、「同じ題名かもしれないので確認」は題名が一意なら止まれると読めた（一意制約があってもSeq Scanは止まらないことを実測で確認している）。①〜⑤と×○で比べた5枚を示し、一致した後の3枚を焦点にした。一致を本2に移してLIMITの図と同じ本にそろえ、前の文の本4も本2に直した。"
```

---

### Task 7: 第1章 `01-index-to-row`（仕組み・手直し）

問いは「番号で探すと、何が変わるのか」。

**Files:**
- Modify: `images/postgresql-query-journey/sources/01-index-to-row.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/01-index-to-row.png`（書き出し）
- Modify: `books/postgresql-query-journey/01-explain-basics.md:299-300`
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 2の部品（`.ipage`・`.page`・`.row`・`.hot`・`.ref`）。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-index-to-row`
Expected: `✗ 01-index-to-row`。「画像内に断り書き」と「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/01-index-to-row.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="610" viewBox="0 0 640 610" role="img" aria-labelledby="title">
  <title id="title">Indexで場所を探し、その行だけ読む</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="610" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">Indexで場所を探し、その行だけ読む</text>
  <rect x="548" y="22" width="68" height="36" rx="18" class="model"/>
  <text x="582" y="47" text-anchor="middle" class="tag">模型</text>
  <g id="index">
    <rect x="56" y="100" width="420" height="170" rx="10" class="ghost"/>
    <rect x="40" y="88" width="420" height="170" rx="10" class="ghost"/>
    <rect x="24" y="76" width="420" height="170" rx="10" class="ipage"/>
    <text x="44" y="108" class="s b">Index books_pkey（番号順）</text>
    <rect x="44" y="124" width="52" height="34" rx="4" class="row"/>
    <text x="70" y="148" text-anchor="middle" class="s">41</text>
    <text x="108" y="148" class="s m">▸ 場所</text>
    <rect x="44" y="164" width="52" height="34" rx="4" class="hot"/>
    <text x="70" y="188" text-anchor="middle" class="s b">42</text>
    <text x="108" y="188" class="s b">▸ 場所</text>
    <rect x="44" y="204" width="52" height="34" rx="4" class="row"/>
    <text x="70" y="228" text-anchor="middle" class="s">43</text>
    <text x="108" y="228" class="s m">▸ 場所</text>
    <text x="24" y="298" class="mono">Index Cond: (id = 42)</text>
    <text x="24" y="328" class="m">Indexも何ページかある</text>
  </g>
  <text x="350" y="300" class="s">場所をたどる</text>
  <g id="table">
    <rect x="24" y="350" width="592" height="160" rx="10" class="page"/>
    <text x="44" y="380" class="s b">表 books のページ</text>
    <rect x="44" y="394" width="330" height="30" rx="4" class="row"/>
    <text x="58" y="416" class="s">41　実験用の本 41</text>
    <rect x="44" y="430" width="330" height="30" rx="4" class="hot"/>
    <text x="58" y="452" class="s b">42　実験用の本 42</text>
    <rect x="44" y="466" width="330" height="30" rx="4" class="row"/>
    <text x="58" y="488" class="s">43　実験用の本 43</text>
  </g>
  <path d="M186 181 C 568 181, 568 445, 380 445" class="ref"/>
  <text x="24" y="548" class="s"><tspan class="mono">Rows Removed by Filter</tspan> なし＝捨てた行がない</text>
  <text x="24" y="582" class="s"><tspan class="mono">shared hit=7</tspan>＝ページを使った回数（Indexも含む）</text>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-index-to-row`
Expected: `images/postgresql-query-journey/01-index-to-row.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 索引の項目「42 ▸ 場所」から、表の行「42　実験用の本 42」へ、灰色の細い矢印が1本だけ届いている。橙の枠は、この矢印の両端（項目42と行42）だけ。
- 「場所をたどる」が矢印の線にかぶっていない（かぶる場合は`x`を左へずらす）。
- 最下段の2行が右端からはみ出していない。
- `Index Cond: (id = 42)`と`shared hit=7`が本文の出力と一致している。

- [ ] **Step 4: 代替テキストとキャプションを直す**

`books/postgresql-query-journey/01-explain-basics.md`で置き換える。

置き換え元：

```markdown
![番号で場所を探し、表から行を取り出す](/images/postgresql-query-journey/01-index-to-row.png)
*Index Scanの模型。索引の内部は第3章で扱います。*
```

置き換え先：

```markdown
![索引の項目42が持つ場所をたどり、表のページから本42の行だけを読む](/images/postgresql-query-journey/01-index-to-row.png)
*索引で行の場所を見つけ、その場所の行だけを読む模型。索引の中身は第3章で扱います。*
```

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "title": "番号で場所を探し、表から行を取り出す",
    "description": "Index Scanの模型 ／ 索引の内部は第3章で扱う"
```

置き換え先：

```json
    "title": "索引で場所を探し、その行だけ読む",
    "description": "仕組み：Index Scanの模型"
```

`images/postgresql-query-journey/README.md`で置き換える。

置き換え元：`| 第1章 | 番号で場所を探し、表から行を取り出す | [SVG](sources/01-index-to-row.svg) | [PNG](01-index-to-row.png) |`

置き換え先：`| 第1章 | 索引で場所を探し、その行だけ読む | [SVG](sources/01-index-to-row.svg) | [PNG](01-index-to-row.png) |`

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（47枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-index-to-row`
Expected: `✓ 01-index-to-row`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/01-index-to-row.svg images/postgresql-query-journey/01-index-to-row.png books/postgresql-query-journey/01-explain-basics.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第1章の索引の図で、項目から行への参照を1本の矢印にする" -m "矢印がパネルからパネルへ引かれ、索引の項目がどの行を指すのかが見えなかった。索引の項目を「キー＋場所」で描き、項目42から行42へ参照の矢印を直接引いた。出力の Index Cond・Rows Removed by Filter が出ないこと・shared hit=7 を図の中に書き込んだ。"
```

---

### Task 8: 第1章 新規 `01-explain-stages`（仕組み・新規）

問いは「EXPLAINとEXPLAIN ANALYZEは、どこまで進んで止まるのか」。`01-explain-basics.md`の表（211〜215行目）の直後に置く。

**Files:**
- Create: `images/postgresql-query-journey/sources/01-explain-stages.svg`
- Create: `images/postgresql-query-journey/01-explain-stages.png`（書き出し）
- Modify: `books/postgresql-query-journey/01-explain-basics.md:215-217`（図を挿入）
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 2の部品（`.step`・`.hot`）。Task 3で直した`README.md`の`01-scan-and-filter`の行（この行の直前に足す）。
- Produces: 処理の段階を白抜きの矢印で並べる描き方。第6章`02-query-stages`の手直しで段を4つに増やして使う。

- [ ] **Step 1: まだ図がないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-explain-stages`
Expected: `✗ 01-explain-stages`、`SVG がない: images/postgresql-query-journey/sources/01-explain-stages.svg`。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/01-explain-stages.svg`を作る。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="410" viewBox="0 0 640 410" role="img" aria-labelledby="title">
  <title id="title">どの段階まで進むか</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="410" fill="#f5f7f9"/>
  <text x="24" y="48" class="h">どの段階まで進むか</text>
  <g id="stages">
    <path d="M176 74 H314 L332 96 L314 118 H176 Z" class="step"/>
    <text x="250" y="104" text-anchor="middle" class="s b">計画する</text>
    <path d="M322 74 H460 L478 96 L460 118 H322 L340 96 Z" class="step"/>
    <text x="400" y="104" text-anchor="middle" class="s b">実行する</text>
    <path d="M468 74 H616 V118 H468 L486 96 Z" class="step"/>
    <text x="548" y="104" text-anchor="middle" class="s b">行を画面へ</text>
  </g>
  <g id="select">
    <text x="24" y="176" class="mono b">SELECT</text>
    <path d="M200 170 H548" fill="none" stroke="#277b74" stroke-width="4"/>
    <circle cx="250" cy="170" r="9" fill="#277b74"/>
    <circle cx="400" cy="170" r="9" fill="#277b74"/>
    <circle cx="548" cy="170" r="9" fill="#277b74"/>
    <text x="200" y="206" class="m">検索結果の行を表示</text>
  </g>
  <g id="explain">
    <text x="24" y="266" class="mono b">EXPLAIN</text>
    <path d="M200 260 H250" fill="none" stroke="#277b74" stroke-width="4"/>
    <path d="M250 260 H548" fill="none" stroke="#b5c2cc" stroke-width="3" stroke-dasharray="8 6"/>
    <circle cx="250" cy="260" r="9" fill="#277b74"/>
    <circle cx="400" cy="260" r="9" fill="#fff" stroke="#b5c2cc" stroke-width="3"/>
    <circle cx="548" cy="260" r="9" fill="#fff" stroke="#b5c2cc" stroke-width="3"/>
    <text x="200" y="296" class="m">計画と見積もりを表示</text>
  </g>
  <g id="analyze">
    <text x="24" y="344" class="mono b">EXPLAIN</text>
    <text x="24" y="372" class="mono b">ANALYZE</text>
    <rect x="466" y="306" width="150" height="34" rx="6" class="hot"/>
    <text x="541" y="330" text-anchor="middle" class="s b">行は出さない</text>
    <path d="M200 356 H400" fill="none" stroke="#277b74" stroke-width="4"/>
    <path d="M400 356 H548" fill="none" stroke="#b5c2cc" stroke-width="3" stroke-dasharray="8 6"/>
    <circle cx="250" cy="356" r="9" fill="#277b74"/>
    <circle cx="400" cy="356" r="9" fill="#277b74"/>
    <circle cx="548" cy="356" r="9" fill="#fff" stroke="#b5c2cc" stroke-width="3"/>
    <text x="200" y="392" class="m">計画＋実際の行数と時間を表示</text>
  </g>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-explain-stages`
Expected: `images/postgresql-query-journey/01-explain-stages.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 3つの白抜きの矢印「計画する」「実行する」「結果を表示」の文字が、矢印の形からはみ出していない。
- SELECTは3つとも塗りの丸、EXPLAINは1つ目だけ、EXPLAIN ANALYZEは2つ目までが塗りの丸で、残りは破線と白い丸。
- 橙の枠「表示しない」がEXPLAIN ANALYZEの行の「結果を表示」の列にだけあり、白い丸や上の行の文字にかぶっていない。

- [ ] **Step 4: 本文に図を入れる**

`books/postgresql-query-journey/01-explain-basics.md`で置き換える。

置き換え元：

```markdown
| `EXPLAIN ANALYZE SELECT ...` | する | 実行計画に、実際の行数や時間を加えたもの |

`EXPLAIN ANALYZE`では、
```

置き換え先：

```markdown
| `EXPLAIN ANALYZE SELECT ...` | する | 実行計画に、実際の行数や時間を加えたもの |

三つの入力が、計画・実行・表示のどこまで進むかを線で比べてください。

![SELECTは計画・実行・表示まで進む。EXPLAINは計画を立てたところで止まり、EXPLAIN ANALYZEは実行まで進んで、結果の行は表示しない](/images/postgresql-query-journey/01-explain-stages.png)
*実線の段階まで進み、破線の段階は行いません。*

`EXPLAIN ANALYZE`では、
```

- [ ] **Step 5: 図の一覧に足す**

`images/postgresql-query-journey/catalog.json`で置き換える（`01-scan-and-filter`の項目の直前に足す）。

置き換え元：

```json
  {
    "name": "01-scan-and-filter",
```

置き換え先：

```json
  {
    "name": "01-explain-stages",
    "chapter": 1,
    "title": "計画・実行・表示のどこまで進むか",
    "description": "仕組み：SELECT・EXPLAIN・EXPLAIN ANALYZEの比較"
  },
  {
    "name": "01-scan-and-filter",
```

`images/postgresql-query-journey/README.md`で、`| 第1章 | 1行のために、100万行を比べた |`で始まる行（Task 3で直した行）の直前に、次の行を足す。

```markdown
| 第1章 | 計画・実行・表示のどこまで進むか | [SVG](sources/01-explain-stages.svg) | [PNG](01-explain-stages.png) |
```

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（48枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-explain-stages`
Expected: `✓ 01-explain-stages`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/01-explain-stages.svg images/postgresql-query-journey/01-explain-stages.png books/postgresql-query-journey/01-explain-basics.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第1章に、EXPLAINがどこまで進むかの図を追加" -m "EXPLAINとEXPLAIN ANALYZEの違いが「する／しない」の表だけで、ANALYZEは実行するのに結果の行を表示しないことが見えにくかった。計画・実行・表示の3段階を白抜きの矢印で並べ、各入力が進む段階を実線、進まない段階を破線で描いた。第6章の処理段階の図と同じ部品にしてある。"
```

---

### Task 9: 第1章 `01-search-window`（問い・手直し）

問いは「画面に出るのは1冊。その1冊を返すまでに、何冊を調べたか」。答え（何冊を調べたか）は描かない。

**Files:**
- Modify: `images/postgresql-query-journey/sources/01-search-window.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/01-search-window.png`（書き出し）
- Modify: `books/postgresql-query-journey/01-explain-basics.md:15-16`
- Modify: `images/postgresql-query-journey/catalog.json`・`index.html`（READMEの見出しは変えない）

**Interfaces:**
- Consumes: Task 2の部品（`.req`・`.flow`・`.spine`）。
- Produces: 問いの型（クリーム色の背景、問いの箱）の描き方。Task 10が合わせる。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window`
Expected: `✗ 01-search-window`。「文字が小さい（22未満）: 18, 17, 21, 14」、「画像内に断り書き」、「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/01-search-window.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="610" viewBox="0 0 640 610" role="img" aria-labelledby="title">
  <title id="title">まずは、1冊だけ探してみる</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="610" fill="#fffdf7"/>
  <text x="24" y="48" class="h">まずは、1冊だけ探してみる</text>
  <g id="screen">
    <rect x="24" y="72" width="592" height="170" rx="10" fill="#fff" stroke="#243b50" stroke-width="2.5"/>
    <path d="M24 110 H616" fill="none" stroke="#243b50" stroke-width="2.5"/>
    <text x="40" y="99" class="s">読書ノート：本を探す</text>
    <rect x="44" y="124" width="300" height="44" rx="8" fill="#e9f3f4" stroke="#243b50" stroke-width="2"/>
    <text x="60" y="154" class="s">実験用の本 42</text>
    <text x="368" y="154" class="b">検索結果：1冊</text>
    <text x="60" y="214" class="s">42　実験用の本 42</text>
    <path d="M320 242 V258 M280 258 H360" fill="none" stroke="#243b50" stroke-width="3" stroke-linecap="round"/>
  </g>
  <g id="arrows">
    <path d="M200 266 V324" class="req"/>
    <text x="228" y="302" class="s brown">題名で探す</text>
    <path d="M440 326 V268" class="flow"/>
    <text x="468" y="302" class="s teal">1冊を返す</text>
  </g>
  <g id="database">
    <rect x="24" y="334" width="592" height="180" rx="12" fill="none" stroke="#243b50" stroke-width="2" stroke-dasharray="8 6"/>
    <text x="40" y="366" class="m">データベースの中（画面からは見えない）</text>
    <rect x="44" y="382" width="552" height="84" rx="6" fill="#f3ede2" stroke="#243b50" stroke-width="2"/>
    <rect x="58" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="75" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="92" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="109" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="126" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="143" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="160" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="177" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="194" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="211" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="228" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="245" y="392" width="12" height="64" rx="2" class="spine"/>
    <text x="320" y="436" text-anchor="middle" class="h">…</text>
    <rect x="383" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="400" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="417" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="434" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="451" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="468" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="485" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="502" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="519" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="536" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="553" y="392" width="12" height="64" rx="2" class="spine"/>
    <rect x="570" y="392" width="12" height="64" rx="2" class="spine"/>
    <text x="320" y="498" text-anchor="middle" class="b">本の一覧　100万冊</text>
  </g>
  <rect x="24" y="530" width="592" height="60" rx="10" fill="#fff0d3" stroke="#243b50" stroke-width="2.5"/>
  <text x="44" y="569" class="b">1冊が返るまでに、何冊を調べた？</text>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-search-window`
Expected: `images/postgresql-query-journey/01-search-window.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 上に検索画面（「検索結果：1冊」）、下に破線の枠「データベースの中」と本棚「本の一覧　100万冊」がある。
- 棚の中のどの本も強調されていない（答えを描いていない）。人物・虫眼鏡・注意書きがない。
- 破線の矢印「題名で探す」（下向き）と実線の矢印「1冊を返す」（上向き）が、画面の台や枠に重なっていない。

- [ ] **Step 4: 代替テキストとキャプションを直す**

`books/postgresql-query-journey/01-explain-basics.md`で置き換える。

置き換え元：

```markdown
![まずは、1冊だけ探してみる](/images/postgresql-query-journey/01-search-window.png)
*学ぶきっかけを描く、説明用の場面。*
```

置き換え先：

```markdown
![検索画面には1冊だけが出ている。その裏のデータベースには本が100万冊あり、1冊を返すまでに何冊を調べたかを問う絵](/images/postgresql-query-journey/01-search-window.png)
*画面に出るのは1冊。その裏に、100万冊の一覧があります。*
```

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "name": "01-search-window",
    "chapter": 1,
    "title": "まずは、1冊だけ探してみる",
    "description": "サービスの場面・学ぶきっかけの絵"
```

置き換え先：

```json
    "name": "01-search-window",
    "chapter": 1,
    "title": "まずは、1冊だけ探してみる",
    "description": "問い：画面の1冊と、裏の100万冊"
```

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（48枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window`
Expected: `✓ 01-search-window`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/01-search-window.svg images/postgresql-query-journey/01-search-window.png books/postgresql-query-journey/01-explain-basics.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第1章の場面の絵に、画面から見えない100万冊を描く" -m "画面の1冊だけが描かれ、調べた件数に当たる絵がなかった。画面の下に、データベースの中の100万冊の棚を描き、「題名で探す」「1冊を返す」の矢印でつないだ。どの本を調べたかは答えになるので描かない。スマホで読めない注意書きと、飾りの人物・虫眼鏡を外した。"
```

---

### Task 10: 第2章 `05-growing-library`（問い・描き直し）

問いは「見つかったところで止めれば、調べる数は減るのか」。今の図の「最後まで探す」は予想2・3の答えなので描かない。

**Files:**
- Modify: `images/postgresql-query-journey/sources/05-growing-library.svg`（全体を置き換える）
- Modify: `images/postgresql-query-journey/05-growing-library.png`（書き出し）
- Modify: `books/postgresql-query-journey/02-linear-search.md:15-16`
- Modify: `images/postgresql-query-journey/catalog.json`・`README.md`・`index.html`

**Interfaces:**
- Consumes: Task 9の問いの型、Task 2の部品（`.step`・`.spine`・`.hot`）。

- [ ] **Step 1: 今の図が約束を満たしていないことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-growing-library`
Expected: `✗ 05-growing-library`。「文字が小さい」、「画像内に断り書き」、「代替テキストが画像の見出しと同じ」が出る。

- [ ] **Step 2: SVGを書く**

`images/postgresql-query-journey/sources/05-growing-library.svg`の全体を次にする。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="530" viewBox="0 0 640 530" role="img" aria-labelledby="title">
  <title id="title">見つかったら、止めていい？</title>
  <defs>
    <marker id="flow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10z" fill="#277b74"/></marker>
    <marker id="req" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0 0L10 5L0 10" fill="none" stroke="#945e11" stroke-width="2"/></marker>
    <marker id="ref" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0L9 4.5L0 9z" fill="#7d93a3"/></marker>
  </defs>
  <style>
text{font-family:"Hiragino Sans","Noto Sans JP",sans-serif;font-size:24px;fill:#243b50}
.h{font-size:30px;font-weight:700}.b{font-weight:700}.s{font-size:22px}.m{font-size:22px;fill:#566c7b}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:22px}.tag{font-size:22px;font-weight:700;fill:#fff}
.teal{fill:#176e65}.brown{fill:#945e11}.real{fill:#176e65}.model{fill:#566c7b}
.panel{fill:#fff;stroke:#cedae1;stroke-width:2}.node{fill:#ecf2f8;stroke:#56738a;stroke-width:2}
.row{fill:#fff;stroke:#448b7c;stroke-width:2}.match{fill:#fff;stroke:#176e65;stroke-width:4}
.page{fill:#f7fbf9;stroke:#6d9f94;stroke-width:2}.ipage{fill:#f4f6f8;stroke:#6b7f8e;stroke-width:2}
.band{fill:#d5dde3;stroke:#92a7b5;stroke-width:2}.skip{fill:none;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.hot{fill:#fff0d5;stroke:#b88020;stroke-width:4}.ghost{fill:#f5f7f9;stroke:#b5c2cc;stroke-width:2;stroke-dasharray:6 5}
.flow{fill:none;stroke:#277b74;stroke-width:3;marker-end:url(#flow)}.req{fill:none;stroke:#945e11;stroke-width:3;stroke-dasharray:8 6;marker-end:url(#req)}
.ref{fill:none;stroke:#7d93a3;stroke-width:2;marker-end:url(#ref)}.step{fill:#fff;stroke:#243b50;stroke-width:2.5}
.spine{fill:#e9f3f4;stroke:#243b50;stroke-width:1.5}
  </style>
  <rect width="640" height="530" fill="#fffdf7"/>
  <text x="24" y="48" class="h">見つかったら、止めていい？</text>
  <g id="screen">
    <rect x="452" y="68" width="164" height="104" rx="8" fill="#fff" stroke="#243b50" stroke-width="2.5"/>
    <path d="M452 100 H616" fill="none" stroke="#243b50" stroke-width="2.5"/>
    <text x="468" y="92" class="s">検索画面</text>
    <text x="468" y="132" class="s b">1冊でよい</text>
    <text x="468" y="162" class="mono">LIMIT 1</text>
  </g>
  <path d="M24 110 H392 V100 L432 128 L392 156 V146 H24 Z" class="step"/>
  <text x="40" y="136" class="s">先頭から順に見る</text>
  <g id="shelf-early">
    <text x="24" y="204" class="s">早く見つかる本：ここで止めていい？</text>
    <rect x="24" y="214" width="592" height="72" rx="6" fill="#f3ede2" stroke="#243b50" stroke-width="2"/>
    <rect x="38" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="55" y="222" width="12" height="56" rx="2" class="hot"/>
    <rect x="72" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="89" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="106" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="123" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="140" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="157" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="174" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="191" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="208" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="225" y="222" width="12" height="56" rx="2" class="spine"/>
    <text x="314" y="260" text-anchor="middle" class="h">…</text>
    <rect x="403" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="420" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="437" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="454" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="471" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="488" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="505" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="522" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="539" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="556" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="573" y="222" width="12" height="56" rx="2" class="spine"/>
    <rect x="590" y="222" width="12" height="56" rx="2" class="spine"/>
  </g>
  <g id="shelf-late">
    <text x="24" y="314" class="s">遅く見つかる本：どこまで見る？</text>
    <rect x="24" y="324" width="592" height="72" rx="6" fill="#f3ede2" stroke="#243b50" stroke-width="2"/>
    <rect x="38" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="55" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="72" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="89" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="106" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="123" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="140" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="157" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="174" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="191" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="208" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="225" y="332" width="12" height="56" rx="2" class="spine"/>
    <text x="314" y="370" text-anchor="middle" class="h">…</text>
    <rect x="403" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="420" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="437" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="454" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="471" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="488" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="505" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="522" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="539" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="556" y="332" width="12" height="56" rx="2" class="spine"/>
    <rect x="573" y="332" width="12" height="56" rx="2" class="hot"/>
    <rect x="590" y="332" width="12" height="56" rx="2" class="spine"/>
  </g>
  <g id="shelf-none">
    <text x="24" y="424" class="s">ない本：何冊見たら「ない」と分かる？</text>
    <rect x="24" y="434" width="592" height="72" rx="6" fill="#f3ede2" stroke="#243b50" stroke-width="2"/>
    <rect x="38" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="55" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="72" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="89" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="106" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="123" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="140" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="157" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="174" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="191" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="208" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="225" y="442" width="12" height="56" rx="2" class="spine"/>
    <text x="314" y="480" text-anchor="middle" class="h">…</text>
    <rect x="403" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="420" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="437" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="454" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="471" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="488" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="505" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="522" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="539" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="556" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="573" y="442" width="12" height="56" rx="2" class="spine"/>
    <rect x="590" y="442" width="12" height="56" rx="2" class="spine"/>
  </g>
</svg>
```

- [ ] **Step 3: 書き出して、見た目を確かめる**

Run: `NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 05-growing-library`
Expected: `images/postgresql-query-journey/05-growing-library.png`と表示される。

ReadツールでPNGを開き、次を確かめる。

- 3段の棚が同じ長さで、1段目は左から2冊目、2段目は右から2冊目だけが橙、3段目は強調なし。
- 「最後まで探す」や冊数など、予想の答えになる文字がない。
- 右上の検索画面（`LIMIT 1`）と白抜きの矢印「先頭から順に見る」が重なっていない。
- 3段目のラベル「ない本：何冊見たら「ない」と分かる？」が右端からはみ出していない。

- [ ] **Step 4: 代替テキストとキャプションを直す**

`books/postgresql-query-journey/02-linear-search.md`で置き換える。

置き換え元：

```markdown
![100万冊から、1冊見つけたら止める？](/images/postgresql-query-journey/05-growing-library.png)
*学ぶきっかけを描く、説明用の場面。棚の絵は実際の行の配置を表していません。*
```

置き換え先：

```markdown
![同じ100万冊の棚が3段あり、目的の本が先頭近くにある段、最後近くにある段、見つからない段で、どこまで見ればよいかを問う絵](/images/postgresql-query-journey/05-growing-library.png)
*3段とも同じ100万冊。目的の本の位置だけが違います。*
```

- [ ] **Step 5: 図の一覧を更新する**

`images/postgresql-query-journey/catalog.json`で置き換える。

置き換え元：

```json
    "title": "100万冊から、1冊見つけたら止める？",
    "description": "サービスの場面・学ぶきっかけの絵"
```

置き換え先：

```json
    "title": "見つかったら、止めていい？",
    "description": "問い：同じ100万冊で、目的の本の位置が違う"
```

`images/postgresql-query-journey/README.md`で置き換える。

置き換え元：`| 第2章 | 100万冊から、1冊見つけたら止める？ | [SVG](sources/05-growing-library.svg) | [PNG](05-growing-library.png) |`

置き換え先：`| 第2章 | 見つかったら、止めていい？ | [SVG](sources/05-growing-library.svg) | [PNG](05-growing-library.png) |`

Run: `node scripts/book-figures/build-index.cjs`
Expected: `index.html を更新しました（48枚）`

- [ ] **Step 6: 約束を満たしたことを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 05-growing-library`
Expected: `✓ 05-growing-library`

- [ ] **Step 7: コミットする**

```bash
git add images/postgresql-query-journey/sources/05-growing-library.svg images/postgresql-query-journey/05-growing-library.png books/postgresql-query-journey/02-linear-search.md images/postgresql-query-journey/catalog.json images/postgresql-query-journey/README.md images/postgresql-query-journey/index.html
git commit -m "docs(query-journey): 第2章の場面の絵を、同じ100万冊で本の位置だけが違う3段の棚にする" -m "小さい棚と大きい棚を比べる絵は、本を増やしていた旧構成の名残で、表の大きさの違いに読めた。「最後まで探す」も直後の予想の答えだった。同じ長さの棚を3段描き、目的の本の位置だけを変えて、どこまで見ればよいかを問う形にした。"
```

---

### Task 11: 通しで確かめ、枚数を更新して ship する

**Files:**
- Modify: `images/postgresql-query-journey/README.md:5`
- Modify: `books/postgresql-query-journey/AGENTS.md:53`

**Interfaces:**
- Consumes: Task 1〜10のすべての成果物、`.claude/launch.json`の`zenn-preview`。

- [ ] **Step 1: 試作の8枚が約束を満たしていることを確かめる**

Run: `node scripts/book-figures/check-figures.cjs 01-search-window 01-explain-stages 01-scan-and-filter 01-index-to-row 05-growing-library 05-linear-scan 05-limit-search 05-limit-bands && node --test scripts/book-figures/check-figures.test.cjs`
Expected: 8枚とも✓、`8枚中 8枚が約束を満たしています`、`ℹ pass 5`。

- [ ] **Step 2: 本文の参照がすべて実在する画像を指していることを確かめる**

Run: `grep -ho '/images/postgresql-query-journey/[^) ]*\.png' books/postgresql-query-journey/*.md | sort -u | while read p; do [ -f ".${p}" ] || echo "ない: ${p}"; done; echo "確認終わり"`
Expected: `確認終わり`だけが表示される（「ない:」の行がない）。

- [ ] **Step 3: Zennのプレビューで、スマホ幅とPC幅の表示を確かめる**

`preview_start`で`zenn-preview`を起動する（ポート8000で、このリポジトリの`zenn preview`がすでに動いていれば、起動せずにそれを使う）。次の2ページで、それぞれ`resize_window`の`mobile`（幅375）と`desktop`に切り替えて`computer`の`screenshot`を撮り、試作の図のところまでスクロールして確かめる。

- `http://localhost:8000/books/postgresql-query-journey/01-explain-basics%252Emd`
- `http://localhost:8000/books/postgresql-query-journey/02-linear-search%252Emd`

確かめること：画像がすべて配信される（Zennは画像を遅延読み込みするので、`complete`ではなく取得で確かめる。`javascript_tool`で`await Promise.all([...document.images].filter(i => i.src.includes('postgresql-query-journey')).map(async i => (await fetch(i.src)).status))`がすべて`200`）。スマホ幅で図の文字が読める。キャプションが画像の直下に斜体で出る。`read_console_messages`の`onlyErrors`にエラーがない。終わったら`resize_window`を`desktop`に戻す。自分で起動した場合だけ`preview_stop`で止める。

- [ ] **Step 4: 図の枚数を更新する**

`images/postgresql-query-journey/README.md`の5行目を置き換える。

置き換え元：

```markdown
序章から第12章まで、計46枚を本文へ掲載しています。序章は導入の絵2枚と技術図2枚です。第4章にはctidの図、第6章にはSQLの処理段階の図を追加しています。[図の一覧](index.html)からまとめて確認できます。
```

置き換え先：

```markdown
序章から第12章まで、計48枚を本文へ掲載しています。序章は導入の絵2枚と技術図2枚です。第4章にはctidの図、第6章にはSQLの処理段階の図を追加しています。第1〜2章の8枚は、[設計書](../../books/postgresql-query-journey/FIGURE-PLAN.md)の型で描き直した試作です。[図の一覧](index.html)からまとめて確認できます。
```

`books/postgresql-query-journey/AGENTS.md`の53行目で置き換える。

置き換え元：`序章〜第12章に計46枚のSVG原本とPNGを制作・掲載済み。`

置き換え先：`序章〜第12章に計48枚のSVG原本とPNGを制作・掲載済み（2026-09-24に第1〜2章の8枚を FIGURE-PLAN.md の型で試作）。`

- [ ] **Step 5: コミットする**

```bash
git add images/postgresql-query-journey/README.md books/postgresql-query-journey/AGENTS.md
git commit -m "docs(query-journey): 図の枚数を48枚に更新し、第1〜2章の試作を記録" -m "第1〜2章に図を2枚足したので、画像の README と AGENTS.md の枚数を直す。第1〜2章の8枚が設計書の型で描き直した試作であることを README に書いた。"
```

- [ ] **Step 6: ship する**

`/ship`の手順で、ブランチ`book-query-journey-figure-pilot`をpushし、`main`向けのPRを作って説明文を書く。説明文は過去のPRと同じ見出し（📋 概要／📸 スクリーンショット／👓 関連PR／📮 レビュワーに伝えたいこと）にし、最後に`🤖 Generated with [Claude Code](https://claude.com/claude-code)`を付ける。スクリーンショットの節には、Step 3で撮ったスマホ幅の画面を載せる代わりに、変更した8枚のPNGのパスを並べる。「レビュワーに伝えたいこと」には、次を書く。

- 試作で決めたいこと：観察の型の帯の描き方（100万行と1行の差を、拡大した1行のカードで見せる方法でよいか）、問いの型で人物を描かない方針でよいか。
- 本文で変えたのは、図の前後の文・キャプション・代替テキストと、第2章89行目の「本4」→「本2」だけ。設計書9章の要確認3件は変えていない。
- `check-figures.cjs --all`では、試作以外の図が約束を満たしていないので✗になる（横展開で直す）。

- [ ] **Step 7: ユーザーに試作の確認を頼む**

PRのURLと、確認してほしい点（上の「試作で決めたいこと」）を伝える。横展開（設計書5章の手順3・4）は、ユーザーの確認を待ってから別の計画にする。

---

## 実装で直した点（2026-09-25）

計画の SVG のまま描くと問題が出た図は、タスクごとのレビューと、ブランチ全体の最終レビューのあとで直した。上の Task 2〜10 の SVG は、直した後の内容に同期してある。

| Task | 図 | 計画のままで出た問題 | 直し方 | 見つけた場面 |
| --- | --- | --- | --- | --- |
| 2 | 部品見本 | 見出しの下に副題があった | 副題を外した | タスクのレビュー |
| 2 | 部品見本 | 破線の例のラベルが「読まない」で、試作の「比べない」と食い違った | 「比べない」にした | 最終レビュー |
| 3 | `01-scan-and-filter` | 結果へ向かう矢印に動詞のラベルがない | 矢印の上に「返す」を足した | タスクのレビュー |
| 3 | `01-scan-and-filter` | 「返す」が矢じりに触れた。Filter の行に出力の`::text`がなかった | 「返す」を上へ離し、Filter の行を出力と同じ字面にした | 最終レビュー |
| 4 | `05-limit-bands` | 「実測 2026-09-23」の札と「ここで止まった」の橙の枠が文字より狭く、文字が線に重なった | 札を幅220にし、文字を中央に置き直した | コントローラーの確認 |
| 4 | `05-limit-bands` | 橙の枠が比べなかった区間の大半を覆い、スマホ幅では橙で埋まった帯に見えた。「42行」に要求の茶色を使った | 橙は帯の先頭の小さな枠だけにし、ラベルを枠なしで帯の中に置いた。「42行」を紺にした | 最終レビュー |
| 6 | `05-linear-scan` | 「一致した後も比べる」に要求の茶色を使った | 紺にした | 最終レビュー |
| 7 | `01-index-to-row` | 参照の矢印を表のページより前に描いたため、表の塗りに矢印の後半と矢じりが隠れた | 矢印を表のページの後ろに描く順へ移した | 実装担当 |
| 7 | `01-index-to-row` | 「shared hit=7＝索引と表のページを使った回数」が実測と違った。7のうち3回は、接続して最初の検索だけに入るシステムカタログの読み取り（同じ接続の2回目は hit=4） | 「ページを使った回数（索引も含む）」にした。画像の中の「（中身は第3章）」を外し、キャプションに残した | 最終レビュー |
| 8 | `01-explain-stages` | 3段目の「結果を表示」と焦点の「表示しない」の真下に、各行の「…を表示」が並び、矛盾して読めた | 3段目を「行を画面へ」、焦点を「行は出さない」、見出しを「どの段階まで進むか」にした | 最終レビュー |
| 9 | `01-search-window` | 矢じり（線の太さに合わせて30単位の大きさになる）がラベルの先頭の文字に触れた | 2つのラベルを右へ14ずらした | タスクのレビュー |
| 2・7 | 部品見本、`01-index-to-row` | 試作の後で、本全体の表記が「索引」から「Index」に変わった（#13、AGENTS.md の約束） | 見出し・ラベル・代替テキスト・キャプション・一覧の「索引」を「Index」にした。見出しが伸びて「模型」の札との間が8に詰まったので、札を幅68にして間を16にした | #13 の取り込み |

道具も最終レビューのあとで直した。書き出しの処理は`scripts/book-figures/export.cjs`にまとめ、Task 1 で置き換えた`images/postgresql-query-journey/export.cjs`は、それを読み込む1行にした（`npm run export`が図の名前を受け取れない古い複製を動かしていたため）。断り書きの検査にはパターン（※、説明用、省略、模式、架空など）を足し、`build-index.cjs`は直接実行したときだけ動くようにした。

横展開の計画に活かすこと：

- 文字のはみ出しは、目で見るだけでは見落とした（実装担当とレビュー担当の両方が見落とした）。ブラウザで文字の実寸（getBBox）を測り、すぐ下に描いた図形と比べる。この試作では SDD の作業用スクリプト（コミットしていない）で測った。横展開では`check-figures.cjs`に取り込み、文字と矢じりの重なりも測る。
- 図に書き込む出力の数値は、同じ接続で2回実行して、1回目だけの読み取り（システムカタログなど）が混ざっていないかを確かめる。内訳を描くときは、その内訳を実測で確かめてからにする。
- 線や矢印は、重なる図形より後に描く。矢じりの近くのラベルは、矢じりの大きさ（線の太さ×10単位）の分だけ離す。
- 焦点の橙の枠は、見せたい位置（止まった位置など）だけに付ける。量を見せる帯の上に大きな枠を重ねない。
- 図の中の言葉（段の名前や焦点のラベル）が、各行の説明文と食い違わないかを読み比べる。
- 約束の「画像の中に置くのは短い見出しと札だけ」は、図の中のラベルと字面上ぶつかる。「画像の中の文字は、見出し・札・部品の名前・矢印の動詞・出力の項目名と値に限り、副題・断り書き・他の章への参照はキャプションへ回す」に言い換える。
- 断り書きの検査は語で拾うので、注意の語を含まない副題（例：「サンプルの2冊・3件で考える」）は通ってしまう。見出しのすぐ下の文や「。」で終わる文を形で拾う検査を足し、「ではない」が正当なラベルに当たったときの扱い（言い換えるか、除外の仕組みを作るか）も決めておく。
- 「索引」は使わず「Index」と書く（AGENTS.md、2026-09-25のユーザー指定）。太字30の「Index」は漢字およそ3文字分の幅を取るので、見出しの言葉を変えたら、札との間隔を測り直す。
