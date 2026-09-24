# 第7章のランキングの計測

第7章 `books/sql-data-structures/07-ranking-revisited.md` は、第6章を終えた状態から取得した `results/ch07-ranking-docker-pg18-20260921.txt` を出典にする。

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch07-ranking.sql
```

`ch07-ranking.sql` は序章のランキング（3 回）、目録を使わせない設定での再現、VACUUM ANALYZE、(finished_at, book_id) の目録での試行（ROLLBACK）、先に数える書き換え（3 回）、集計表 `weekly_read_counts` の作成と目録（残す）、集計表からのランキング（3 回）、結果の確認、推定と実測を出す。実行後、読者の DB に `weekly_read_counts`（43MB）が残る。

| 案 | 計画の要点 | Execution Time |
| --- | --- | --- |
| いまの状態（finished_at の目録あり） | Bitmap Heap Scan → Hash Join → HashAggregate → top-N | 5863.6 / 5392.6 / 5340.1 ms |
| 目録を使わせない（序章の形） | Seq Scan → Hash Join → HashAggregate → top-N | 5456.9 ms |
| 案 1 (finished_at, book_id) の目録 | Index Only Scan → Hash Join → HashAggregate → top-N | 5542.5 ms |
| 案 2 先に数える書き換え | Bitmap Heap Scan → HashAggregate → top-N → Nested Loop 20 回 | 2167.6 / 2123.7 / 2157.2 ms |
| 案 3 集計表 | Index Only Scan（20 行）→ Nested Loop 20 回 | 0.134 / 0.042 / 0.039 ms |

2 回目の内訳（おおよそ）: 探す 0.78 秒、ハッシュ表 0.20 秒、組み合わせ 2.90 秒、数える 1.62 秒、並べる 0.09 秒。推定 rows 5,077,400 に対し実測 4,999,999。

---

# 第5章の上位 20 件の計測

第5章 `books/sql-data-structures/05-top-n-heap.md` は、第4章を終えた状態から取得した `results/ch05-top-n-docker-pg18-20260921.txt` を出典にする。

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch05-top-n.sql
```

`ch05-top-n.sql` は 1 週間分 `ORDER BY finished_at DESC LIMIT 20`（3 回）、LIMIT 1000 / 100000 / 1000000、全件 LIMIT 20、`CREATE INDEX reading_records_finished_at_idx`、目録ありの LIMIT 20（3 回）と 1 週間分 LIMIT 20、目録ありで第4章の全部並べる SQL（副作用、約 28 秒）、1 時間分を出す。実行後、読者の DB に `reading_records_finished_at_idx`（181MB）が残る。

| SQL | Sort Method | メモリ / ディスク | Execution Time |
| --- | --- | --- | --- |
| 1 週間 LIMIT 20 | top-N heapsort | 26kB | 1248.6 / 1056.1 / 1094.7 ms |
| 1 週間 LIMIT 1000 | top-N heapsort | 115kB | 1064.5 ms |
| 1 週間 LIMIT 100000 | top-N heapsort | 12758kB | 1298.5 ms |
| 1 週間 LIMIT 1000000 | external merge | Disk 127232kB | 2218.8 ms |
| 全件 LIMIT 20 | top-N heapsort | 26kB | 2333.4 ms |
| 目録あり 全件 LIMIT 20 | なし（Index Scan Backward） | 23 ページ | 0.176 / 0.016 / 0.012 ms |
| 目録あり 1 週間を全部並べる | なし（Index Scan Backward） | 5,005,762 ページ | 28297.5 ms |

# 第6章の JOIN の計測

第6章 `books/sql-data-structures/06-join.md` は、第5章を終えた状態から取得した `results/ch06-join-docker-pg18-20260921.txt` を出典にする。

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch06-join.sql
```

`ch06-join.sql` は 20 件に題名を付ける JOIN（3 回、Nested Loop）、1 週間分・1 日分・1 時間分の JOIN（Hash Join）、`SET enable_hashjoin = off`（Merge Join）と `SET enable_mergejoin = off`（Nested Loop）、`SET work_mem = '8MB'`（Batches 8）、GROUP BY book_id（HashAggregate）、1 冊の本の読了記録（目録なし、`CREATE INDEX reading_records_book_id_idx`、目録あり）を出す。実行後、読者の DB に `reading_records_book_id_idx`（148MB）が残る。

| SQL | 方法 | Execution Time |
| --- | --- | --- |
| 20 件に題名 | Nested Loop（内側 loops=20、Memoize） | 48.6 / 10.7 / 8.0 ms |
| 1 週間分に題名 | Hash Join（Hash 70,692kB、作成約 0.3 秒） | 3944.2 / 3879.9 ms |
| 1 日分に題名 | Hash Join | 932.7 ms |
| 1 時間分に題名 | Hash Join（Hash 作成 0.25 秒） | 336.8 ms |
| 1 日分、hashjoin off | Merge Join（Sort 46,898kB） | 817.6 ms |
| 1 日分、mergejoin も off | Nested Loop（内側 71 万回） | 2164.9 ms |
| 1 日分、work_mem 8MB | Hash Join（Batches 8） | 904.1 ms |
| 1 週間分 GROUP BY book_id | HashAggregate（73,753kB、100 万グループ） | 2130.5 ms |
| 1 冊の読了記録、目録なし | Hash Join + Seq Scan 2,000 万行 | 2056.1 ms |
| 1 冊の読了記録、目録あり | Nested Loop | 0.254 / 0.049 ms |

---

# 第4章の並べ替えの計測

第4章 `books/sql-data-structures/04-sort.md` は、第3章を終えた状態から読者と同じ手順で取得した `results/ch04-sort-docker-pg18-20260921.txt` を出典にする。

## 再実行

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch04-sort.sql
```

`ch04-sort.sql` は `reading_records` を TRUNCATE してから序章の大きい方と同じ式で 2,000 万件を作り直し（約 13 秒）、1 時間分・1 日分・1 週間分を `ORDER BY finished_at DESC` で並べる EXPLAIN ANALYZE（各 3 回）、`SET work_mem = '1GB'` での 1 週間分（2 回）、books の `ORDER BY id / title LIMIT 20`、参考の count を出す。
実行後、読者の DB の `reading_records` は 2,000 万件（845MB、108,109 ページ）になる。序章の大きい方と同じデータ。

## 計測結果

| 期間 | 件数 | Sort Method | メモリ / ディスク | 並べ替えの時間（Sort の最初の actual time − Seq Scan の全体）3 回 | Execution Time 3 回 |
| --- | --- | --- | --- | --- | --- |
| 1 時間 | 29,762 | quicksort | 1699kB | 7.3 / 4.4 / 4.4 ms | 694.7 / 667.9 / 666.1 ms |
| 1 日 | 714,284 | quicksort | 46898kB | 117.8 / 106.1 / 116.4 ms | 920.3 / 846.1 / 853.7 ms |
| 1 週間 | 4,999,999 | external merge | Disk 127216kB | 1186.3 / 941.1 / 922.7 ms | 2532.6 / 2296.8 / 2267.4 ms |
| 1 週間、work_mem 1GB | 4,999,999 | quicksort | 352858kB | 793.4 / 919.1 ms | 3169.1 / 3125.2 ms |

毎回の Seq Scan は shared hit 約 16,200、read 約 91,850（合計 108,109 ページ、shared_buffers 128MB）。books の `ORDER BY id LIMIT 20` は Index Scan（4 ページ）、`ORDER BY title LIMIT 20` は Index Scan（12 ページ）で Sort なし。

---

# 第3章の木構造（B-tree）の計測

第3章 `books/sql-data-structures/03-btree-index.md` は、第2章を終えた状態（本 100 万冊、設定 3 つ）から読者と同じ手順で取得した `results/ch03-btree-docker-pg18-20260921.txt` を出典にする。

## 再実行

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch03-btree.sql
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch03-cleanup.sql
```

`ch03-btree.sql` は pageinspect の導入、`bt_metap` と `bt_page_stats` による books_pkey の段数と段ごとのページ数、番号検索の Buffers、一時テーブル（1,000 冊、10 万冊）の目録の段数、目録なしの 1 万冊追加 3 回、`CREATE INDEX books_title_idx`、題名検索の Buffers、目録ありの 1 万冊追加 3 回、前方一致 LIKE を出す。`ch03-cleanup.sql` は `VACUUM books` で取り消した追加の跡を片付け、ページ数が 7,353 に戻ることを確かめる。
実行後、読者の DB には `books_title_idx`（約 40MB）と `pageinspect` 拡張が残る。

## 計測結果

- books_pkey: 2,745 ページ、level 2（3 段）。根 1、中間 10、葉 2,733 ページ。
- 番号検索 `id = 42`: 初回 7 ページ、2 回目以降 4 ページ。`id = 999958` は 4 ページ。
- 一時テーブルの目録: 1,000 冊は 5 ページで 2 段、10 万冊は 276 ページで 2 段。
- `CREATE INDEX books_title_idx`: 約 14.1 秒。4,961 ページ、39MB、3 段。題名検索は 4 ページ（初回は hit 1 + read 3）。
- 1 万冊の追加: 目録なし 19.6 / 18.7 / 21.3 ms、目録あり 287.8 / 245.6 / 240.3 ms。
- LIKE '実験用の本 4295%' は Seq Scan（照合順序 en_US.utf8）。
- VACUUM 後: books 7,353 ページ 57MB、books_pkey 2,772、books_title_idx 5,056 ページ。

---

# 第2章の全件探索の計測

第2章 `books/sql-data-structures/02-linear-search.md` は、第1章の状態（本 1,000 冊）から読者と同じ手順で本を 10 万冊、100 万冊に増やしながら取得した `results/ch02-linear-search-docker-pg18-20260921.txt` を出典にする。

## 再実行

第1章の `ch01-setup.sql` を実行した直後の状態から始める。

```bash
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch02-settings.sql
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch02-linear-search.sql
```

`ch02-settings.sql` は `ALTER DATABASE` で並列 0、JIT off、work_mem 64MB を設定する（序章の実測条件に揃える）。設定は再接続後に有効になる。
`ch02-linear-search.sql` は 1,000 冊の題名検索、10 万冊への INSERT と題名検索 3 回、10 万冊での `LIMIT 1`（先頭近く、真ん中、末尾近く、比較用の LIMIT なし）、100 万冊への INSERT と題名検索 3 回、先頭ページの行数、100 万冊での番号検索を出す。
実行後、読者の DB の `books` は 100 万冊になる。以降の章はこの状態から続ける。

## 計測結果

| 冊数 | relpages | Buffers shared hit | Rows Removed by Filter | Execution Time 3 回 (ms) |
| --- | --- | --- | --- | --- |
| 1,000 | 8 | 8 | 999 | 0.041（1 回） |
| 100,000 | 736 | 736 | 99,999 | 3.230 / 5.601 / 3.380 |
| 1,000,000 | 7,353 | 7,353 | 999,999 | 33.259 / 32.160 / 32.632 |

10 万冊の `LIMIT 1`: 先頭近く 2 ページ・41 行、真ん中 369 ページ・49,999 行、末尾近く 736 ページ・99,957 行。LIMIT なしの末尾近くは 736 ページ・99,999 行。先頭ページの行数は 136（`ctid` で数えた。本文では割り算だけで示し、この SQL は載せていない）。100 万冊の番号検索は 7 ページと 4 ページ。

## 同期スキャンの観測

100 万冊で `LIMIT 1` を付けた題名検索は、読み始めの位置が状況で変わる（synchronize_seqscans）。最初の実行で先頭近くの本が 3,691 ページを読んだ観測は `results/ch02-syncscan-observed-docker-pg18-20260921.txt`（画面からの転記）に、再現を試みて 3 回とも 2 ページだった記録は `results/ch02-syncscan-note-docker-pg18-20260921.txt` にある。本文では 10 万冊で `LIMIT 1` を試し、100 万冊の現象は発展の注記に置く。

---

# 第1章の EXPLAIN 基礎の計測

第1章 `books/sql-data-structures/01-explain-basics.md` は、読者と同じ Docker の手順で取得した `results/ch01-explain-basics-docker-pg18-20260921.txt` を出典にする。
序章の計測（Homebrew の PostgreSQL 18.3、一時テーブル）とは環境が違うので、章ごとの `:::details` に版を書いて区別する。

## 再実行

```bash
docker run --name reading-log-lab \
  -e POSTGRES_PASSWORD=reading-log-local \
  -e POSTGRES_DB=reading_log \
  -d postgres:18
docker exec reading-log-lab pg_isready -U postgres -d reading_log
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch01-setup.sql
docker exec -i reading-log-lab psql -X -U postgres -d reading_log -f - < _drafts/sql-data-structures/experiments/ch01-explain.sql
```

`ch01-setup.sql` は本 1,000 冊と読了記録 2 万件を通常テーブルとして作る。本文に載せる SQL と同じ内容。
`ch01-explain.sql` は題名検索と番号検索の `EXPLAIN` と `EXPLAIN ANALYZE`（各 3 回）、`pg_class` のページ数、`EXPLAIN INSERT` の前後の件数を出す。
設定は Docker 既定値のまま（`work_mem = 4MB`、`max_parallel_workers_per_gather = 2`、`jit = on`）。
コンテナは後の章でも使うので `docker stop reading-log-lab` で止め、削除しない。

## 計測結果

2026-09-21、Apple Silicon の macOS、Docker の `postgres:18`（PostgreSQL 18.6）。

| SQL | ノード | 推定 rows | actual rows | Rows Removed by Filter | Execution Time 3 回 (ms) |
| --- | --- | --- | --- | --- | --- |
| `WHERE title = '実験用の本 42'` | Seq Scan on books | 1 | 1.00 | 999 | 0.090 / 0.049 / 0.385 |
| `WHERE id = 42` | Index Scan using books_pkey | 1 | 1.00 | なし | 0.147 / 0.272 / 0.041 |

`books` は 8 ページ、`books_pkey` は 5 ページ、`reading_records` は 109 ページ。
`EXPLAIN INSERT` の前後で `books` の件数は 1,000 のまま。

---

# 序章の「今週よく読まれた本」計測

現在の序章は `weekly-ranking.sql` の結果を使用する。計算済みスコアを取り出す以前の実験とは別のSQLであり、前後の改善比較ではない。

## 再実行

リポジトリのルートから、ローカルの実験用DBに接続する。

```bash
psql -X -d postgres -f _drafts/sql-data-structures/experiments/weekly-ranking.sql
psql -X -d postgres -v book_count=1000 -v record_count=20000 -f _drafts/sql-data-structures/experiments/weekly-ranking.sql
```

大きい方は本100万冊・読了記録2,000万件。データ領域は約902MB（本の主キーなどは別）を使う。一時テーブルで完結し、最後にROLLBACKする。文ごとのタイムアウトは90秒。既存テーブルは変更しない。

## 計測結果

2026-09-21、Apple M1 Pro / 32GiB RAM / PostgreSQL 18.3 Homebrew。work_mem=64MB、並列実行/JIT無効。読了日時は2026-08-24からの4週間に分布し、9月14日以上・21日未満を対象週にする。人気の偏りは再現していない合成データ。

| 条件 | 3回のpsql経過時間（ms） | 中央値（ms） |
| --- | --- | --- |
| 本1,000冊・記録2万件 | 2.466 / 2.140 / 2.017 | 2.140 |
| 本100万冊・記録2,000万件 | 4630.241 / 4553.647 / 4531.875 | 4553.647 |

生ログ：`results/weekly-ranking-small-pg18.3-20260921.txt` と `results/weekly-ranking-large-pg18.3-20260921.txt`。

大きい方の対象週は4,999,999件。実行計画には読了記録のSeq Scan、Hash Join、HashAggregate、top-N heapsortが現れた。別途計測したEXPLAINのExecution Timeは4611.826ms。集計結果は100万グループ、最後に20行を返す。LIMITだけで集計対象が20件になるわけではない。

読者向けの序章では結果の時間と問いまでを示し、実行計画の解釈と改善の検証は後続章で行う。集計・JOINを含むので、問題の回収を「並べる」の章だけで完結するとは約束しない。

---

## 以前の試作の記録（計算済みスコア）

# 序章のランキング計測

2026-09-21に実行。Apple M1 Pro、32GiB RAM、arm64 macOS、PostgreSQL 18.3 Homebrew。

## 再実行

ローカルの実験用DBに接続する。以下はリポジトリのルートで実行する。接続先に応じて `-d` などを変更する。

```bash
psql -X -d postgres -f _drafts/sql-data-structures/experiments/ranking-million.sql
psql -X -d postgres -v book_count=1000 -f _drafts/sql-data-structures/experiments/ranking-million.sql
```

一時テーブルとトランザクション内の設定だけを使い、最後にROLLBACKする。既存テーブルは変更しない。スコア生成の乗算は100万件でも整数オーバーフローしないようbigintで行う。

## 結果と解釈

- 1,000件の通常SELECT：5回の中央値0.136ms。
- 1,000,000件の通常SELECT：5回の中央値73.166ms。範囲67.907〜74.413ms。
- 主キーのインデックスは存在するが、人気順のインデックスはない。
- 別途取得した100万件の実行計画：Seq Scanが100万行を返し、top-N heapsortを経て20行を返す。Execution Timeは89.972ms。
- 通常SELECTの時間はpsqlのクライアント経過時間。EXPLAINの計測値とは混ぜない。
- 一時テーブル、work_mem=64MB、並列実行/JIT無効。データ投入・ANALYZE・件数確認後の連続測定。コールドキャッシュや同時アクセスの実験ではない。
- 100万件で数秒かかる、利用者が待てずに画面を閉じる、という状況は再現していない。序章はデータ増加による処理時間の伸びと、その理由が分からない困りごとへ改稿した。
- 生ログは `results/` に保存。後続章で実行計画を解説する材料としても使う。
