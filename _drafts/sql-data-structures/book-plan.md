# 本全体の残り計画（2026-09-21 21:20、ユーザー指示「最後までやっておいて」を受けて作成）

進め方は第1章・第2章と同じ。章ごとに、設計メモ → 実測（Docker `reading-log-lab`）→ Sonnet 初稿 → Opus 独立レビュー → 修正と再レビュー → Fable 全体レビュー → 修正と再確認 → 統合。ユーザーへの確認は挟まず、判断は設計メモに記録する。

| 章 | ファイル | 状態 | 題材 | 主な学び |
| --- | --- | --- | --- | --- |
| 序章 | 00-prologue.md | 完成（ユーザー執筆） | ランキングが約 4.6 秒 | 問い |
| 第1章 | 01-explain-basics.md | 完成 | 題名検索と番号検索 | EXPLAIN、EXPLAIN ANALYZE、rows と Rows Removed |
| 第2章 | 02-linear-search.md | 完成 | 本を 100 万冊へ | Buffers のページ数、全件探索 O(n)、LIMIT と位置 |
| 第3章 | 03-btree-index.md | 制作中 | 主キーの目録の中身、題名にインデックス | B-tree、木の高さ、O(log n)、インデックスの代償 |
| 第4章 | 04-sort.md | 制作中 | 読了記録を 2,000 万件へ、新しい順の一覧 | ソート、O(n log n)、work_mem、外部ソート、shared read、インデックスで並び順を得る |
| 第5章 | 05-top-n-heap.md | 制作中 | 新しい順に 20 件 | top-N heapsort、ヒープ、finished_at の目録、目録の副作用 |
| 第6章 | 06-join.md | 制作中 | 本と読了記録を組み合わせる | Nested Loop、Hash Join、Merge Join、ハッシュ表、集計 |
| 第7章 | 07-ranking-revisited.md | 実測済み | 序章のランキングを直す | 多段の計画を読む、推定と実測、改善の選択と検証 |
| 付録 | 99-appendix.md | 未着手 | 実験 SQL 一覧、EXPLAIN の読み方早見表、用語対応 | |

## 読者の DB の状態の推移

- 第1章: books 1,000 冊、reading_records 2 万件（Docker 既定設定）
- 第2章: 設定 3 つ（並列 0、JIT off、work_mem 64MB）。books 100 万冊
- 第3章: books_title_idx を作る（残す）
- 第4章: reading_records を TRUNCATE して序章の大きい方と同じ式で 2,000 万件へ（実測済み）。work_mem を一時的に変える実験は SET で行い、RESET で戻す
- 第5章: finished_at のインデックスを作る（残す。実測済み）
- 第6章: book_id のインデックスを作る（残す。実測済み）。enable_* は SET で切り替えて RESET で戻す
- 第7章: (finished_at, book_id) のインデックスは ROLLBACK で試すだけ。集計表 weekly_read_counts は残す（実測済み）

## 章をまたぐ約束（回収先）

- 「read の中身は後の章で扱います」（第2章）→ 第4章で shared read と shared_buffers
- 「並列読みの仕組みは発展として後で扱います」（第2章）→ 第7章の発展の注記、または付録
- 「なぜインデックスがあると調べる行が減るのか」（第1章、第2章）→ 第3章
- 「番号検索が 100 万冊でも 7 ページ、末尾側で 4 ページ」（第2章）→ 第3章で木の高さと初回の余分な読みとして説明、または「どちらも数ページ」に丸める
- 「読了記録はいずれ 2,000 万件」（第2章）→ 第5章
- 序章の問い「何件の読了記録を調べればよいか」「どこに時間がかかるか」→ 第7章で回収

## 規約（全章共通）

- 文体、段落書式、見出し、インラインコードの空白、Mermaid（subgraph と ~~~ を使わない）、公式引用の形式は第1章・第2章と同じ。
- 数値は実測ログのみ。出力は 1 回目を転記。3 回分は :::details。
- 各章の :::details に計測条件（日付、Apple Silicon の macOS、Docker postgres:18 = PostgreSQL 18.6、設定 3 つ）と生ログの保存先。
- 「ヒープ」の語は第5章でデータ構造として導入し、PostgreSQL の表の格納先を指すヒープとは区別する。それまでは「表のページ」。
- コントローラーの通読メモは修正ブリーフに全件転記する（第2章での漏れの再発防止）。
- 分量はコードブロックを除いて 7,000〜9,500 字。

## 試し測りで分かったこと（第5章〜第7章の設計に使う。2026-09-21 22:20、Docker、読了記録 2,000 万件）

生の出力: scratchpad の `ch05/probe-ch05.txt`、`ch05/probe-ranking.txt`（一時的な場所。章の実測時に `_drafts` へ正式なログを取り直す）

### 第5章（上位 20 件、ヒープ、目録で並べ替えを消す）
- 1 週間分 `ORDER BY finished_at DESC LIMIT 20`: Sort Method top-N heapsort、Memory 26kB。並べ替えの時間は約 0.3 秒（全部並べると約 1.1 秒）。読むページは全件読みと同じ 108,109。
- LIMIT 1000 は top-N 115kB、LIMIT 100000 は top-N 12,758kB、LIMIT 1000000 は external merge（上位 k 件が work_mem に収まらないと全部並べる）。
- 全 2,000 万件から LIMIT 20 も top-N 26kB、2.3 秒。
- `CREATE INDEX reading_records_finished_at_idx ON reading_records (finished_at)`: 約 5.5 秒、23,124 ページ、181MB、level 2（3 段）。
- 目録あり: 全件 LIMIT 20 は Index Scan Backward、23 ページ、0.02 ms。1 週間分 LIMIT 20 も 23 ページ。
- 副作用: 目録あり で 1 週間分を全部並べる（第4章の SQL）と、Index Scan Backward が選ばれ 27 秒、5,004,456 ページ読み（表のページを飛び飛びに何度も読む）。目録なしの Seq Scan + Sort は 2.3 秒。第5章で正直に示し、理由（推定と実測のずれ、飛び飛びの読み）は第7章へ。
- 目録あり で 1 時間分は Bitmap Heap Scan（目録で場所を集めてから表を読む）。
- count(*) は Index Only Scan（VACUUM 前は Heap Fetches あり、VACUUM 後は 0）。

### 第6章（JOIN）
- 序章のランキングの Hash Join: books 100 万冊を Hash に載せる（Buckets 1,048,576、Memory 69,607kB、Batches 1）。work_mem 64MB × hash_mem_multiplier 2 = 128MB に収まる。
- 「1 冊の本の読了記録一覧」（book_id の絞り込み）は book_id に目録がないので Seq Scan になるはず。book_id の目録を作ると Nested Loop + Index Scan になる見込み（未計測）。Merge Join は enable_* の切り替えで観察する（未計測）。

### 第7章（ランキングを直す）
- 目録なし: 5.64 秒（Docker）。内訳: Seq Scan 約 1.0 秒、Hash Join が終わるまで約 4.0 秒、HashAggregate（100 万グループ、98MB）が終わるまで約 5.5 秒、top-N は約 0.1 秒。
- finished_at の目録あり: Bitmap Heap Scan になるが 5.48 秒。ほぼ変わらない。
- (finished_at, book_id) の目録あり: Index Only Scan になるが 5.44 秒。JOIN と集計が支配的。
- 改善の本命は「先に読了記録だけを本ごとに数えて上位 20 冊を選び、そのあと 20 冊だけ books と結合する」書き換え（第6章の学びの応用）。見込み約 2 秒（未計測）。さらに集計結果を保存する表（鮮度との交換）。
- 序章の Homebrew 18.3 での 4.6 秒と Docker 18.6 での 5.6 秒は環境の差。第7章は Docker の値で語り、序章の値は「序章で測った値」として区別する。
