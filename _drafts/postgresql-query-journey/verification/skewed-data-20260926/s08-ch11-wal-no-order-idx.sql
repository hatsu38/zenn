\set ON_ERROR_STOP on
SET max_parallel_workers_per_gather=0; SET jit=off; SET work_mem='4MB';
-- 本文の注記どおり、第8章の reading_records_order_idx がない状態で UPDATE の WAL を採る
DROP INDEX IF EXISTS reading_records_order_idx;
CREATE INDEX reading_records_visibility_idx ON reading_records (book_id, finished_at);
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
DROP INDEX reading_records_visibility_idx;
