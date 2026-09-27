# 技術書典用の紙面（試作）

『図解 SQLの裏側で動くアルゴリズムとPostgreSQLの仕組み』を、技術書典で頒布する紙の本（JIS B5、本文モノクロ）と電子版の PDF に組むための仕組みです。原稿の正本は `books/postgresql-query-journey/` の Zenn の原稿のままにし、ここでは変換と組版だけを行います。

## 組み方

```bash
cd print/postgresql-query-journey
node convert.mjs 01-explain-basics 06-process-and-execution
npx -y @vivliostyle/cli@11.3.3 build
```

- `node convert.mjs` に章のスラッグを渡すとその章だけ、何も渡さなければ `config.yaml` の全章を変換します。
- 印刷用は `output/print.pdf` にできます。
- 電子版は、変換と組版の両方に `EDITION=ebook` を付けます（`EDITION=ebook node convert.mjs ...`、`EDITION=ebook npx -y @vivliostyle/cli@11.3.3 build`）。`output/ebook.pdf` にできます。
- `build/`・`output/`・`.vivliostyle/` は生成物なので Git に入れません。

### 入稿用の PDF を作る

```bash
cd print/postgresql-query-journey
node convert.mjs
NODE_PATH=../../scripts/book-figures/node_modules node export-hires.cjs
npx -y @vivliostyle/cli@11.3.3 build --crop-marks --bleed 3mm -o output/print-trim.pdf
```

- `export-hires.cjs` は、図の原本（SVG）を4倍の解像度（横2,560px）で書き出し、`build/src/images` の図を置き換えます。掲載用のPNG（横1,280px）はB5の本文幅（146mm）で約220dpiですが、4倍なら約445dpiになります。Playwrightは本体の `scripts/book-figures/node_modules` を使います。
- `--crop-marks --bleed 3mm` でトンボと3mmの塗り足しが付きます。用紙はB5の外側に余白の付いた214×289mmになります。塗り足しの幅やPDFの形式は、印刷所の入稿条件に合わせて変えてください。
- 電子版には `export-hires.cjs` を使わず、掲載用のPNGのままにします（ファイルが大きくなりすぎないため）。

## 変換スクリプトが Zenn の書き方をどう移すか

| Zenn の原稿 | 紙面 |
| --- | --- |
| コード枠 | 1行ずつ字下げの幅を持たせ、折り返した続きをその行の字下げより右から始める。長い実行計画でも木の形が崩れない |
| ```` ```sql:実行結果 ```` | 枠の上に「実行結果」のラベルを付け、地に薄い網を掛ける |
| `:::message` | 実線の囲み記事 |
| `:::details` | 紙では畳めないので、今の位置のまま破線で囲み、左上に種類のラベルを付ける（2026-09-28 のユーザー判断）。予想や課題の直後の枠は黒地の「答え」、長い実行結果を畳んだ枠は「実行結果」、それ以外は「補足」。どれを「答え」にするかは `convert.mjs` の `ANSWER_DETAILS` と、見出しが「考え方」かどうかで決める |
| 画像と直後の斜体の行 | 図とキャプション |
| 脚注 `[^label]` | その語が出てくるページの下の注 |
| 外部リンク | 印刷用は、リンクの文字の後ろに注を付けて URL を注に書く。電子版はリンクのまま |
| 別の章へのリンク | 文字だけ残す |

フォントは、PDF に埋め込んで頒布できる OFL の Noto Serif JP（本文）、Noto Sans JP（見出し）、BIZ UDGothic（コード）を Google Fonts から読み込んでいます。

## 試作で分かったこと（2026-09-28）

- 2章で21ページ。本全体ではおよそ160〜180ページになる見込み。
- 半角100字を超える実行計画の行も、ぶら下げて折り返せば字下げの親子を読める。本文の書き直しは要らない見込み。
- 確かめた2枚の図は、グレーにしても実線と破線、濃淡で区別できた。残りの図は未確認。
- 図を次のページへ送ると、前のページの下が大きく空くことがある。
- 全章（序章から「おわりに」まで15章、図55枚）を組むと163ページになった。`:::details` のラベルは「答え」8、「実行結果」7、「補足」17。
- 扉（`parts/00-title.md`）、目次（Vivliostyle の `toc`。章と節の見出しとページ番号）、奥付（`parts/99-colophon.md`）を加えた（2026-09-28）。扉と奥付にはページ番号を出さない。
- 奥付の著者・サークル名・連絡先・印刷所・正誤表のURLは「（要記入）」のまま。入稿の前に必ず埋める。
- 56枚の図をグレーで並べて確かめ、色だけで意味を伝えている図や、読めなくなる図はなかった（2026-09-28）。
- `pdfinfo` で調べると、「name token is longer than what the specification says it can be」という警告が大量に出る。日本語の見出しから作られるリンク先の名前が長いため。PDFは開けるが、印刷所の入稿チェックで問題にならないかを確かめる。
- ページ数は、#60・#61 の内容を含まない時点で186ページ（扉・目次・付録2つ・奥付を含む）。無線綴じは4ページ単位のことが多いので、白ページを足して合わせる。日光企画のオンデマンドは162ページ以上だと締め切りが3営業日早まる。
- まだ決めていないこと: 表紙、図の前にできる空白の調整、印刷所の入稿条件。
