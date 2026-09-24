\set ON_ERROR_STOP on
\pset pager off
\if :{?book_count}
\else
  \set book_count 1000000
\endif
\if :{?record_count}
\else
  \set record_count 20000000
\endif
BEGIN;
SET LOCAL statement_timeout = '90s';
SET LOCAL work_mem = '64MB';
SET LOCAL max_parallel_workers_per_gather = 0;
SET LOCAL jit = off;
CREATE TEMP TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
) ON COMMIT DROP;
CREATE TEMP TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
) ON COMMIT DROP;
INSERT INTO books
SELECT n, '実験用の本 ' || n FROM generate_series(1, :book_count) AS n;
-- 直近4週間の読了記録。日時・本の割当は再現可能な架空データ。
INSERT INTO reading_records
SELECT ((n::bigint * 7919) % :book_count) + 1,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, :record_count) AS n;
ANALYZE books;
ANALYZE reading_records;
SELECT version();
SELECT count(*) AS book_count FROM books;
SELECT count(*) AS total_records,
       count(*) FILTER (WHERE finished_at >= timestamp '2026-09-14'
                        AND finished_at < timestamp '2026-09-21') AS weekly_records
FROM reading_records;
SELECT pg_size_pretty(pg_relation_size('books')) AS books_size,
       pg_size_pretty(pg_relation_size('reading_records')) AS records_size;
SELECT tablename, indexdef FROM pg_indexes
WHERE schemaname LIKE 'pg_temp_%' AND tablename IN ('books', 'reading_records');
SHOW work_mem;
SHOW max_parallel_workers_per_gather;
SHOW jit;
\timing on
\echo '計測1'
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
\echo '計測2'
\g
\echo '計測3'
\g
\timing off
\echo '計測後の実行計画'
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
ROLLBACK;
