\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
\echo === ranking ===
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
\echo === size ===
SELECT pg_size_pretty(pg_total_relation_size('books')) AS books_with_index,
       pg_size_pretty(pg_total_relation_size('reading_records')) AS records,
       pg_size_pretty(pg_database_size(current_database())) AS database;
\echo === chapter03 ===
CREATE INDEX books_title_idx ON books (title);
ANALYZE books;
\echo === chapter06 ===
EXPLAIN SELECT id, title FROM books ORDER BY title LIMIT 3;
\echo === chapter07 ===
SELECT count(*) FROM reading_records;
