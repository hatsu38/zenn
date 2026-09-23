\pset pager off
SELECT version();
SHOW work_mem;

\echo '--- 0. いまの表と目録'
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname IN ('books', 'books_pkey', 'books_title_idx', 'reading_records', 'reading_records_finished_at_idx', 'reading_records_book_id_idx') ORDER BY relname;

\echo '--- 1. 序章のランキング（いまの状態、1回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
\echo '--- 1. ランキング（2回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
\echo '--- 1. ランキング（3回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;

\echo '--- 2. 目録を使わせない（序章のときの形。この接続だけ）'
SET enable_bitmapscan = off;
SET enable_indexscan = off;
EXPLAIN ANALYZE
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
RESET enable_bitmapscan;
RESET enable_indexscan;

\echo '--- 3. 案1: 読了日時と本の番号の目録（Index Only Scan）。VACUUM ANALYZE してから、ROLLBACK で試す'
VACUUM ANALYZE reading_records;
BEGIN;
CREATE INDEX reading_records_finished_at_book_id_idx ON reading_records (finished_at, book_id);
EXPLAIN ANALYZE
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size FROM pg_class WHERE relname = 'reading_records_finished_at_book_id_idx';
ROLLBACK;

\echo '--- 4. 案2: 先に数えて、上位 20 冊だけ本と組み合わせる（1回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC;
\echo '--- 4. 案2（2回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC;
\echo '--- 4. 案2（3回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC;

\echo '--- 5. 案3: 集計結果を保存する表'
\timing on
CREATE TABLE weekly_read_counts AS
SELECT book_id, count(*) AS read_count
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
GROUP BY book_id;
CREATE INDEX weekly_read_counts_idx ON weekly_read_counts (read_count DESC, book_id ASC);
ANALYZE weekly_read_counts;
\timing off
SELECT count(*) AS book_rows, pg_size_pretty(pg_relation_size('weekly_read_counts')) AS size FROM weekly_read_counts;
\echo '--- 5. 集計表からランキング（1回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM weekly_read_counts AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC
LIMIT 20;
\echo '--- 5. 集計表（2回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM weekly_read_counts AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC
LIMIT 20;
\echo '--- 5. 集計表（3回目）'
EXPLAIN ANALYZE
SELECT b.id, b.title, c.read_count
FROM weekly_read_counts AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC
LIMIT 20;
\echo '--- 5. 結果が同じことの確認（上位 20 冊）'
SELECT b.id, b.title, c.read_count
FROM weekly_read_counts AS c
JOIN books AS b ON b.id = c.book_id
ORDER BY c.read_count DESC, b.id ASC
LIMIT 20;

\echo '--- 6. 推定と実測: 1 週間分の行数'
EXPLAIN SELECT count(*) FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21';
SELECT count(*) AS actual_rows FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21';
SELECT attname, n_distinct FROM pg_stats WHERE tablename = 'reading_records' ORDER BY attname;
