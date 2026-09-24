# 教材図の原本と掲載用画像

SVGを原本とし、PNGは原本から書き出します。PNGへ直接加筆すると次の書き出しで失われるため、修正はSVGに行ってください。

序章から第12章まで、計46枚を本文へ掲載しています。序章は導入の絵2枚と技術図2枚です。第4章にはctidの図、第6章にはSQLの処理段階の図を追加しています。[図の一覧](index.html)からまとめて確認できます。

| 章 | 題材 | SVG原本 | 掲載用PNG |
| --- | --- | --- | --- |
| 序章 | この本で、一緒に調べること | [SVG](sources/00-book-sketch.svg) | [PNG](00-book-sketch.png) |
| 序章 | こんな読書記録サービスを作ります | [SVG](sources/00-reading-service.svg) | [PNG](00-reading-service.png) |
| 序章 | 本の冊数と、読了記録の件数 | [SVG](sources/00-books-and-records.svg) | [PNG](00-books-and-records.png) |
| 序章 | 20冊を返すまでに、何をしている？ | [SVG](sources/00-ranking-question.svg) | [PNG](00-ranking-question.png) |
| 第1章 | まずは、1冊だけ探してみる | [SVG](sources/01-search-window.svg) | [PNG](01-search-window.png) |
| 第1章 | 1行のために、100万行を比べた | [SVG](sources/01-scan-and-filter.svg) | [PNG](01-scan-and-filter.png) |
| 第1章 | 番号で場所を探し、表から行を取り出す | [SVG](sources/01-index-to-row.svg) | [PNG](01-index-to-row.png) |
| 第2章 | 100万冊から、1冊見つけたら止める？ | [SVG](sources/05-growing-library.svg) | [PNG](05-growing-library.png) |
| 第2章 | 見つけても、そこで終わりとは限らない | [SVG](sources/05-linear-scan.svg) | [PNG](05-linear-scan.png) |
| 第2章 | LIMIT 1でも、探す量は変わる | [SVG](sources/05-limit-search.svg) | [PNG](05-limit-search.png) |
| 第3章 | 8を探す：範囲を選んでから、値を探す | [SVG](sources/06-btree-path.svg) | [PNG](06-btree-path.png) |
| 第3章 | 4以上8以下なら、隣の葉も読む | [SVG](sources/06-range-scan.svg) | [PNG](06-range-scan.png) |
| 第3章 | 目録も大きい。それでも速い？ | [SVG](sources/06-catalog-question.svg) | [PNG](06-catalog-question.png) |
| 第4章 | 索引をたどって、表の行へ届く | [SVG](sources/03-index-reference.svg) | [PNG](03-index-reference.png) |
| 第4章 | 表の中にページ、ページの中に行 | [SVG](sources/03-pages-and-rows.svg) | [PNG](03-pages-and-rows.png) |
| 第4章 | 同じ1,000行でも、8ページと32ページ | [SVG](sources/03-row-width.svg) | [PNG](03-row-width.png) |
| 第4章 | 本の一覧は、どこに保存される？ | [SVG](sources/03-storage-question.svg) | [PNG](03-storage-question.png) |
| 第4章 | ctid = (0,1) が指す場所 | [SVG](sources/03-ctid-location.svg) | [PNG](03-ctid-location.png) |
| 第5章 | ページの保存場所と、計算の作業場所 | [SVG](sources/04-memory-regions.svg) | [PNG](04-memory-regions.png) |
| 第5章 | ファイルのページを、メモリで再利用する | [SVG](sources/shared-buffer-reuse.svg) | [PNG](shared-buffer-reuse.png) |
| 第5章 | 同じ検索を、もう一度 | [SVG](sources/04-repeat-observation.svg) | [PNG](04-repeat-observation.png) |
| 第6章 | 接続ごとにプロセスが動く | [SVG](sources/02-connections.svg) | [PNG](02-connections.png) |
| 第6章 | Index Scanから、Limitへ行が渡る | [SVG](sources/02-execution-tree.svg) | [PNG](02-execution-tree.png) |
| 第6章 | 画面の向こうで、SQLが動く | [SVG](sources/02-client-scene.svg) | [PNG](02-client-scene.png) |
| 第6章 | SQLの文字列から、検索結果が返るまで | [SVG](sources/02-query-stages.svg) | [PNG](02-query-stages.png) |
| 第7章 | メモリに収まらないときの並べ替え | [SVG](sources/07-external-sort.svg) | [PNG](07-external-sort.png) |
| 第7章 | 二つの並びを、比べながら合流する | [SVG](sources/07-merge-cards.svg) | [PNG](07-merge-cards.png) |
| 第7章 | 読み終えた順に、並べたい | [SVG](sources/07-recent-records.svg) | [PNG](07-recent-records.png) |
| 第8章 | 候補を絞る方法と、途中で止まる方法 | [SVG](sources/08-top-n-vs-index.svg) | [PNG](08-top-n-vs-index.png) |
| 第8章 | 上位3枚を保つ：入れ替えるのはどれ？ | [SVG](sources/top-three-heap.svg) | [PNG](top-three-heap.png) |
| 第8章 | 画面に欲しいのは、最新20件 | [SVG](sources/08-twenty-window.svg) | [PNG](08-twenty-window.png) |
| 第9章 | 先に分類し、同じ箱の中で照合する | [SVG](sources/09-hash-join.svg) | [PNG](09-hash-join.png) |
| 第9章 | 並んだ二つの入力を、先頭から合わせる | [SVG](sources/09-merge-join.svg) | [PNG](09-merge-join.png) |
| 第9章 | 記録を1件取り出すたびに、本を探す | [SVG](sources/09-nested-loop.svg) | [PNG](09-nested-loop.png) |
| 第9章 | 本の番号だけでは、題名が分からない | [SVG](sources/09-title-lookup.svg) | [PNG](09-title-lookup.png) |
| 第10章 | 入口の見積もりが、後ろの判断に響く | [SVG](sources/10-estimate-propagation.svg) | [PNG](10-estimate-propagation.png) |
| 第10章 | 同じ「1種類」でも、9,000行と1,000行 | [SVG](sources/10-selectivity.svg) | [PNG](10-selectivity.png) |
| 第10章 | 索引があるのに、なぜ使わない？ | [SVG](sources/10-planner-choice.svg) | [PNG](10-planner-choice.png) |
| 第11章 | 読む時点によって、見える版が変わる | [SVG](sources/11-snapshots.svg) | [PNG](11-snapshots.png) |
| 第11章 | 索引だけで返せるかは、可視性にもよる | [SVG](sources/11-visibility-map.svg) | [PNG](11-visibility-map.png) |
| 第11章 | ログの保存と、ページの書き出し | [SVG](sources/11-wal-and-pages.svg) | [PNG](11-wal-and-pages.png) |
| 第11章 | 題名を直している間に、読まれたら？ | [SVG](sources/11-editing-scene.svg) | [PNG](11-editing-scene.png) |
| 第12章 | 表示は軽くなる。集計の更新は必要。 | [SVG](sources/12-preaggregation.svg) | [PNG](12-preaggregation.png) |
| 第12章 | 上位を選んでから題名を付ける | [SVG](sources/12-ranking-after.svg) | [PNG](12-ranking-after.png) |
| 第12章 | 題名を付けてから、上位を選ぶ | [SVG](sources/12-ranking-before.svg) | [PNG](12-ranking-before.png) |
| 第12章 | 今度は、根拠を持って選べる | [SVG](sources/12-decision-notebook.svg) | [PNG](12-decision-notebook.png) |

## 編集する

原本は幅640のSVGです。文字は編集可能な`text`要素、図形は`rect`や`path`、図全体または各コマは`diagram`や`step-1`などのIDを持つグループにしています。SVG対応のベクター編集ソフト、またはテキストエディタで修正できます。使用ソフトによって読み込み結果が異なるため、保存後に書き出したPNGも確認してください。

色と文字の指定はSVG内の`style`にあります。フォントはHiragino Sans、Noto Sans JP、sans-serifの順です。今回のPNGはmacOSのHiragino Sansで出力しました。他のOSではNoto Sans JPをインストールしてから出力し、折り返しやはみ出しを確認してください。フォントは同梱していません。

図の設計意図・用語と模型の対応は [制作方針](../../books/postgresql-query-journey/ILLUSTRATION-GUIDE.md) にあります。

新しく描く図と描き直す図は、[部品見本](parts/figure-parts.svg)の`<defs>`と`<style>`を写して使います。行カード・ページ枠・索引の項目・計画のノード・量の帯・矢印・札の見た目がそろいます。見本の見た目は[PNG](parts/figure-parts.png)で確認できます。

## PNGを再出力する

PNGを書き出すには、Playwrightをインストールした環境で次を実行します。

```sh
NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs
```

`sources/`内のSVGをすべてChromiumで描画し、フォントの読み込み後に2倍解像度でPNGを書き出します。出力先はこのREADMEと同じディレクトリです。同名のPNGは更新されます。元のSVGは変更しません。

図の名前を渡すと、その図だけを書き出します。変更していない図のPNGに差分を出さないため、ふだんはこちらを使います。

```sh
NODE_PATH=./scripts/book-figures/node_modules node images/postgresql-query-journey/export.cjs 01-scan-and-filter 05-limit-bands
```

`.svg`で終わるパスを渡すと、そのSVGを同じ場所のPNGへ書き出します（例：`parts/figure-parts.svg`）。Playwrightは`scripts/book-figures`で`npm install`して入れます。

PNGは横1280ピクセルで、高さは図ごとに異なります。共有バッファの配置図は1280×1818、ヒープの4コマは1280×3580ピクセルです。本文では横幅に合わせて縮小されます。文字やコマの配置を変えたら、幅360pxの表示も確認してください。

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

## 本文に掲載する

```md
![絵を見なくても変化が伝わる代替テキスト](/images/postgresql-query-journey/shared-buffer-reuse.png)
*説明用の模型。どの条件の例なのかを補足する。*
```

本文で見る目的を示し、図の後で変化と理由を説明します。実測値ではない図には模型と明記し、数値や構造の正確さを確認してから掲載します。

新構成用の独立コピーです。ファイル名の先頭番号は元の章番号を保持し、所属はcatalog.jsonと本文で管理します。
