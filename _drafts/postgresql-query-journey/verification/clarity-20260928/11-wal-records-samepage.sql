-- 2026-09-28 PostgreSQL 18.6（lab: postgresql-structures-lab-db-1, DB reading_map）。第11章の WAL: records=4 の内訳を確かめるため。
-- すべて BEGIN〜ROLLBACK の中で実行し、作った Index も ROLLBACK で消えた。WAL の一覧は pg_waldump -p $PGDATA/pg_wal -s lsn1 -e lsn2。
-- 日時を1秒ずらす更新。HOT にならず新しい版は同じページ→records=3（UPDATE＋INSERT_LEAF×2）
SET max_parallel_workers_per_gather = 0; SET jit = off; SET work_mem = '4MB';
BEGIN;
CREATE INDEX reading_records_visibility_idx ON reading_records (book_id, finished_at);
SELECT ctid, xmin, xmax FROM reading_records WHERE book_id = 42;
SELECT pg_current_xact_id() AS xid, pg_current_wal_insert_lsn() AS lsn1 \gset
EXPLAIN (ANALYZE, BUFFERS, WAL, COSTS OFF, TIMING OFF)
UPDATE reading_records SET finished_at = finished_at + interval '1 second' WHERE book_id = 42;
SELECT pg_current_wal_insert_lsn() AS lsn2 \gset
SELECT ctid, xmin, xmax FROM reading_records WHERE book_id = 42;
\echo xid=:xid lsn1=:lsn1 lsn2=:lsn2
ROLLBACK;
