# Bitmap Scan の出現条件と、可視性マップ・WAL の観察（2026-09-25）

タイトル『SQLの裏側で動いているデータ構造とアルゴリズム ─ PostgreSQLの実行計画を読みながら確かめる』から導いた三つのテスト（T1 名前のある構造か / T2 ランキングSQLで動くか / T3 実行計画に出るか）で、Bitmap Scan・VACUUM・WAL を本文に入れられるかを確かめた。実行は `experiment.sql`、出力は `output.txt`。

## 環境

- postgresql-structures-lab の `db`（PostgreSQL 18.6、arm64）、`reading_map`
- 本と同じ設定: `max_parallel_workers_per_gather = 0`、`jit = off`、`work_mem = '4MB'`
- `reading_records` は 200 万件、`finished_at` は 2026-08-24 〜 2026-09-20。Index は `BEGIN` 内で作り `ROLLBACK` で消したので lab には残っていない

## 結果

| 観察 | 結果 |
|---|---|
| A. 序章のランキングSQL（1週間 = 499,998 件、25%） | `finished_at` の Index を張ると **Bitmap Index Scan → Bitmap Heap Scan** を選ぶ。Heap Blocks: exact=10811（= 表の全ページ） |
| B. 期間を 1日 / 1時間 / 1分 に狭める | 71,427 / 2,974 / 50 件のすべてで Bitmap。**Index Scan は一度も選ばれない** |
| C. コスト比較（1週間） | Bitmap 28,945 / Seq Scan 40,811 / Index Scan 58,746 |
| D. `work_mem = '64kB'` + `enable_seqscan = off` | Heap Blocks: exact=471 **lossy=10340**、Rows Removed by Index Recheck: 1,434,353 |
| E. `UPDATE` を `EXPLAIN (ANALYZE, WAL)` | `WAL: records=1499 fpi=501 bytes=4206051` が出る。SELECT では WAL 行が出ない |
| E. Index Only Scan の Heap Fetches | UPDATE 前 0 → UPDATE 後 **4102**（VACUUM は `BEGIN` 内で実行できないので、戻る観察は第11章の既存手順で） |

`pg_stats` の `finished_at` の correlation は 0.0066。読了記録は日時順に並んでいないので、1日分（3.6%）でも 10,811 ページ全部に散っている。Bitmap Heap Scan はページ番号順にまとめて読むので、散った行を Index Scan で 1 行ずつ辿るより安く見積もられ、Index Scan が選ばれない。

## 本への反映案

- 第3章「11冊と90万冊」の間に三つ目の方法として Bitmap を初出させる。相関が低いと Index Scan は出ないことも、ここで pg_stats の correlation と結ぶ
- 第12章「Index の追加」で、序章の SQL そのものが Bitmap を選ぶことを見せる（A の計画）
- 第7章の `work_mem` と同じ操作で lossy を出せる（D）。ビットマップも作業領域に収まらないと粗くなる
- 第11章は「1ページに数ビット」の二つ目として可視性マップを Bitmap から引き取り、UPDATE の観察を `EXPLAIN (ANALYZE, WAL)` に変えて WAL を実行計画の出力として扱う

## 追記（2026-09-25）: 第11章の手順に WAL オプションを足した再実行

`ch11-wal-option.sql` / `ch11-wal-option-output.txt`。章と同じ手順（Index 作成 → VACUUM → 検索 → UPDATE → 検索 → VACUUM → 検索 → Index 削除）で、UPDATE と検索に `EXPLAIN (ANALYZE, BUFFERS, WAL)` を付けた。

- UPDATE（本42の2行）: `Buffers: shared hit=20 dirtied=3`、`WAL: records=6 fpi=2 bytes=16786`。SELECT には WAL の行が出ない
- Heap Fetches は 0 → 4 → **4**。章の表（2026-09-22）では 0 に戻ったが、今回は戻らなかった。原因は別の接続（pid 22521、psql）が 2026-09-24 16:00 UTC から `idle in transaction` のまま `backend_xid = 813` を持っていたこと。`VACUUM (VERBOSE)` は `2 are dead but not yet removable`、`removable cutoff: 813` と報告した。本42の新しい版の `xmin` は 826 で、813 より新しいので回収できない。章の「長く終わらないトランザクションがあると片付けられない」の実例として本文に足した
- lab には第8章の `reading_records_order_idx` が無い状態で実行した（本の流れでは存在するので、読者の `dirtied` は Index の分だけ増えうる）。lab の設定: `wal_log_hints = off`、`data_checksums = on`。残っていた接続は他のセッションのものなので終了させていない
