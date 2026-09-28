\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
BEGIN;
CREATE INDEX c1_visibility_idx ON reading_records (book_id, finished_at);
UPDATE reading_records SET finished_at = finished_at + interval '1 second' WHERE book_id = 42;
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables WHERE relname = 'reading_records';
SELECT ctid, xmin, xmax FROM reading_records WHERE book_id = 42;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT book_id, finished_at FROM reading_records WHERE book_id = 42 ORDER BY finished_at DESC, book_id ASC;
SELECT count(*) AS index_items_for_42
FROM generate_series(1, (pg_relation_size('c1_visibility_idx') / 8192)::int - 1) AS blk,
     LATERAL bt_page_items('c1_visibility_idx', blk) i
WHERE i.data LIKE '2a 00 00 00 00 00 00 00 %' AND (SELECT type FROM bt_page_stats('c1_visibility_idx', blk)) = 'l';
ROLLBACK;
VACUUM reading_records;
SELECT relallvisible, relpages FROM pg_class WHERE relname = 'reading_records';
