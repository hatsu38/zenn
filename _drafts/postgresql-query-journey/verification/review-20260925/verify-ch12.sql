\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
\timing on
-- 対象週の件数と read_count の分布
SELECT count(*) AS week_records FROM reading_records
WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21';
SELECT read_count, count(*) AS books
FROM (SELECT book_id, count(*) AS read_count FROM reading_records
      WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21'
      GROUP BY book_id) t
GROUP BY read_count ORDER BY read_count DESC;
-- 全期間での分布（本ごとの記録数）
SELECT c, count(*) FROM (SELECT book_id, count(*) c FROM reading_records GROUP BY book_id) t GROUP BY c ORDER BY c;
-- ranking_before
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
-- ranking_after
EXPLAIN (ANALYZE, BUFFERS)
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
-- 第8章の日時Indexを作った場合（ROLLBACKで戻す）
BEGIN;
CREATE INDEX reading_records_order_idx ON reading_records (finished_at DESC, book_id ASC);
ANALYZE reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS)
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
ROLLBACK;
