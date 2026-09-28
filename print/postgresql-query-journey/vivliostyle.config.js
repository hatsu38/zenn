// 技術書典用の紙面を組む設定。先に `node convert.mjs` で build/src を作ってから使う。
//   印刷用: npx @vivliostyle/cli build
//   電子版: EDITION=ebook npx @vivliostyle/cli build
//   入稿用: 図を高解像度にして（export-hires.cjs）、トンボと塗り足しを付ける（--crop-marks --bleed 3mm）
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
  // 扉、目次、本文の各章、奥付の順。目次は章と節（h2）までを載せる
  entry: ['00-title.md', { rel: 'contents', title: '目次' }, ...chapters.map((slug) => `${slug}.md`), '99-colophon.md'],
  toc: { title: '目次', sectionDepth: 2 },
  output: [`output/${edition}.pdf`],
  workspaceDir: '.vivliostyle',
};
