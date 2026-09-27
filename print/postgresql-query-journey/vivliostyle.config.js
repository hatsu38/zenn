// 技術書典用の紙面を組む設定。先に `node convert.mjs` で build/src を作ってから使う。
//   印刷用: npx @vivliostyle/cli build
//   電子版: EDITION=ebook npx @vivliostyle/cli build
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const edition = process.env.EDITION === 'ebook' ? 'ebook' : 'print';
const chapters = JSON.parse(readFileSync(join(__dirname, 'build', 'src', 'chapters.json'), 'utf8'));

module.exports = {
  title: '図解 SQLの裏側で動くアルゴリズムとPostgreSQLの仕組み',
  language: 'ja',
  size: 'JIS-B5',
  theme: [`theme/book.css`, `theme/${edition}.css`],
  entryContext: 'build/src',
  entry: chapters.map((slug) => `${slug}.md`),
  output: [`output/${edition}.pdf`],
  workspaceDir: '.vivliostyle',
};
