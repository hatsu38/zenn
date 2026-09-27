\pset pager off
SET max_parallel_workers_per_gather = 0; SET jit = off; SET work_mem = '4MB';
SELECT count(DISTINCT date(finished_at)) AS days FROM reading_records;
BEGIN;
CREATE INDEX reading_records_day_book_idx ON reading_records ((date(finished_at)), book_id);
ANALYZE reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records WHERE book_id = 42;
ROLLBACK;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records WHERE book_id = 42;
