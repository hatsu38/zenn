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

if (require.main === module) main();
