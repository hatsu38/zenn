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

## 変換スクリプトが Zenn の書き方をどう移すか

| Zenn の原稿 | 紙面 |
| --- | --- |
| コード枠 | 1行ずつ字下げの幅を持たせ、折り返した続きをその行の字下げより右から始める。長い実行計画でも木の形が崩れない |
| ```` ```sql:実行結果 ```` | 枠の上に「実行結果」のラベルを付け、地に薄い網を掛ける |
| `:::message` | 実線の囲み記事 |
| `:::details` | 破線で挟んだ囲み。紙では畳めないので、答えがそのまま見える（扱いは未決） |
| 画像と直後の斜体の行 | 図とキャプション |
| 脚注 `[^label]` | その語が出てくるページの下の注 |
| 外部リンク | 印刷用は、リンクの文字の後ろに注を付けて URL を注に書く。電子版はリンクのまま |
| 別の章へのリンク | 文字だけ残す |

フォントは、PDF に埋め込んで頒布できる OFL の Noto Serif JP（本文）、Noto Sans JP（見出し）、BIZ UDGothic（コード）を Google Fonts から読み込んでいます。

## 試作で分かったこと（2026-09-28、第1章と第6章）

- 2章で21ページ。本全体ではおよそ160〜180ページになる見込み。
- 半角100字を超える実行計画の行も、ぶら下げて折り返せば字下げの親子を読める。本文の書き直しは要らない見込み。
- 確かめた2枚の図は、グレーにしても実線と破線、濃淡で区別できた。残りの図は未確認。
- 図を次のページへ送ると、前のページの下が大きく空くことがある。
- まだ決めていないこと: `:::details`（32個）の答えの置き場所、表紙、奥付、正誤表と問い合わせ先、トンボと塗り足し（印刷所の入稿条件に合わせる）。
