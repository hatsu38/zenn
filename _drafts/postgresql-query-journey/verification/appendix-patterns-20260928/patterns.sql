\pset pager off
SET max_parallel_workers_per_gather = 0; SET jit = off; SET work_mem = '4MB';
SELECT indexname, indexdef FROM pg_indexes WHERE tablename IN ('books','reading_records') ORDER BY 1;
-- P1 関数で包む
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records
WHERE date(finished_at) = date '2026-09-14';
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-15';
-- P2 前方一致
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title LIKE '実験用の本 4200%';
BEGIN;
CREATE INDEX books_title_pattern_idx ON books (title text_pattern_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title LIKE '実験用の本 4200%';
ROLLBACK;
-- P4 複合Indexの列の順番
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records WHERE book_id = 42;
BEGIN;
CREATE INDEX reading_records_book_first_idx ON reading_records (book_id, finished_at);
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records WHERE book_id = 42;
ROLLBACK;
-- P6 大きな OFFSET
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
ORDER BY finished_at DESC, book_id ASC
LIMIT 20 OFFSET 100000;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
ORDER BY finished_at DESC, book_id ASC
LIMIT 20;
