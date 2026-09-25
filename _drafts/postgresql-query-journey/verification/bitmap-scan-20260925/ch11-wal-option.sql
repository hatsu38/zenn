-- 第11章の Heap Fetches の実験に EXPLAIN (ANALYZE, BUFFERS, WAL) を足す（2026-09-25）。章と同じ手順で、Index は最後に消す。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SHOW wal_log_hints;
SHOW data_checksums;
CREATE INDEX reading_records_visibility_idx
ON reading_records (book_id, finished_at);
VACUUM (ANALYZE) reading_records;
\echo '=== VACUUM 後の検索'
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
\echo '=== UPDATE を WAL 付きで観察'
EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
\echo '=== UPDATE 後の検索（WAL 付き）'
EXPLAIN (ANALYZE, BUFFERS, WAL)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
VACUUM (ANALYZE) reading_records;
\echo '=== 再び VACUUM 後の検索'
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
DROP INDEX reading_records_visibility_idx;
