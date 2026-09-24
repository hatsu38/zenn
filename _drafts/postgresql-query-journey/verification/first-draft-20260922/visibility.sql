\set ON_ERROR_STOP on
\pset pager off
CREATE INDEX reading_records_visibility_idx
ON reading_records (book_id, finished_at);
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;

UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
DROP INDEX reading_records_visibility_idx;
