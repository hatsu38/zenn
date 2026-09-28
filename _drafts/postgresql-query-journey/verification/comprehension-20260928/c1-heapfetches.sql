\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
BEGIN;
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE INDEX c1_visibility_idx ON reading_records (book_id, finished_at);
SELECT ctid, book_id, finished_at FROM reading_records WHERE book_id = 42;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT book_id, finished_at FROM reading_records WHERE book_id = 42 ORDER BY finished_at DESC, book_id ASC;
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
SELECT ctid, xmin, xmax, book_id FROM reading_records WHERE book_id = 42;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT book_id, finished_at FROM reading_records WHERE book_id = 42 ORDER BY finished_at DESC, book_id ASC;
-- Index の中で book_id = 42 を指す項目
WITH leaf AS (
  SELECT (bt_page_items('c1_visibility_idx', blk)).*, blk
  FROM generate_series(1, (pg_relation_size('c1_visibility_idx') / 8192)::int - 1) AS blk
)
SELECT blk, itemoffset, ctid, dead FROM leaf
WHERE ctid IN (SELECT t.ctid FROM heap_page_items(get_raw_page('reading_records', 0)) t WHERE false)
   OR data LIKE '2a 00 00 00 00 00 00 00%';
ROLLBACK;
