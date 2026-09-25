# 2026-09-26 既定の設定での実行計画（第1章のコラム用）

- PostgreSQL 18.6（Docker `postgres:18`、aarch64）。使い捨てのコンテナに新しい DB を作り、lab の main の `sql/01/00-setup.sql` で第1章のデータを用意した直後に実行した。
- 設定は既定のまま（`max_parallel_workers_per_gather = 2`、`jit = on`、`work_mem = 4MB`）。本書の共通設定の SET は実行していない。
- 実行した SQL は、第1章の題名検索（`title = '実験用の本 42'`）と序章のランキング SQL。`EXPLAIN (ANALYZE, BUFFERS)` で採った。
- 結果は `default-settings.log`。題名検索は Gather＋Parallel Seq Scan（Workers Launched: 2、loops=3）、ランキングは Gather Merge＋Parallel Hash Join で、見積もりの cost が 149,844 と jit_above_cost の既定値 100,000 を超えたので JIT の節が出た。
