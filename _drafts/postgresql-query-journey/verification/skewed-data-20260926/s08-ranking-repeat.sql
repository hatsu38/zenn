\set ON_ERROR_STOP on
SET max_parallel_workers_per_gather=0; SET jit=off; SET work_mem='4MB';
CREATE TEMP VIEW ranking_before AS
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;

CREATE TEMP VIEW ranking_after AS
SELECT b.id, b.title, top_books.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS top_books
JOIN books AS b ON b.id = top_books.book_id
ORDER BY top_books.read_count DESC, b.id ASC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_after;

\echo BENCH before 1
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_before;

\echo BENCH before 2
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_before;

\echo BENCH before 3
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_before;

\echo BENCH after 1
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_after;

\echo BENCH after 2
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_after;

\echo BENCH after 3
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ranking_after;

\echo BENCH preaggregated 1
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT b.id,b.title,w.read_count FROM weekly_read_counts w JOIN books b ON b.id=w.book_id ORDER BY w.read_count DESC,w.book_id ASC LIMIT 20;

\echo BENCH preaggregated 2
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT b.id,b.title,w.read_count FROM weekly_read_counts w JOIN books b ON b.id=w.book_id ORDER BY w.read_count DESC,w.book_id ASC LIMIT 20;

\echo BENCH preaggregated 3
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT b.id,b.title,w.read_count FROM weekly_read_counts w JOIN books b ON b.id=w.book_id ORDER BY w.read_count DESC,w.book_id ASC LIMIT 20;
