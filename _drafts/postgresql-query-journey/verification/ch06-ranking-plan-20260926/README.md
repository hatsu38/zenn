# 2026-09-26 第6章の時点のランキングの計画

- PostgreSQL 18.6（Docker `postgres:18`、aarch64）。使い捨てのコンテナに新しい DB を作り、lab の main の `sql/01/00-setup.sql`（人気の偏りあり）で第1章のデータを用意し、第3章の `books_title_idx` だけを足した。第6章の時点の状態（読了記録にはまだ Index がない）。
- 本書の共通設定（並列実行と JIT は無効、`work_mem = 4MB`）で、序章のランキング SQL を `EXPLAIN (ANALYZE, BUFFERS)` で2回実行した。どちらも同じ形の計画（Limit → Sort（top-N heapsort）→ HashAggregate → Hash Join → Seq Scan on reading_records と Hash → Seq Scan on books）で、rows も同じだった。
- 本文には1回目の出力を載せた。図 `02-ranking-plan-tree` の rows もこの出力から写した。
