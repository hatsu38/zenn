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

test('findDisclaimers：既存の図にある注意書きの言い回しも拾い、図のラベルは拾わない', () => {
  const notes = ['行の配置・空き領域は省略した模型。', 'ページ内の行数は説明用。総ページ数は実測。', '※ 同じ本の再読も記録します', '架空の画面イメージ', 'まとまりの個数と容量は模式的'];
  const labels = ['本42', '実測 2026-09-23', '比べない', '999,999行（最後の1行は比べない）', 'データベースの中（画面からは見えない）', 'Rows Removed by Filter なし＝捨てた行がない'];
  const svg = [...notes, ...labels].map(text => `<text>${text}</text>`).join('');
  assert.deepEqual(findDisclaimers(svg), notes);
});
