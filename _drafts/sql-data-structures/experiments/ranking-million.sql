\set ON_ERROR_STOP on
\pset pager off
\if :{?book_count}
\else
  \set book_count 1000000
\endif
BEGIN;
SET LOCAL max_parallel_workers_per_gather = 0;
SET LOCAL work_mem = '64MB';
SET LOCAL jit = off;
CREATE TEMP TABLE ranking_books (
    id bigint PRIMARY KEY,
    title text NOT NULL,
    popularity_score integer NOT NULL CHECK (popularity_score >= 0)
) ON COMMIT DROP;
INSERT INTO ranking_books
SELECT n, '実験用の本 ' || n, ((n::bigint * 7919) % 10000)::integer
FROM generate_series(1, :book_count) AS n;
ANALYZE ranking_books;
SELECT version();
SELECT count(*) AS book_count FROM ranking_books;
SELECT pg_size_pretty(pg_relation_size('ranking_books')) AS table_size;
SELECT indexdef FROM pg_indexes
WHERE schemaname LIKE 'pg_temp_%' AND tablename = 'ranking_books';
SHOW work_mem;
SHOW max_parallel_workers_per_gather;
SHOW jit;
SHOW shared_buffers;
SHOW temp_buffers;
-- データ投入・件数確認の後に同じSELECTを5回計測する。
-- psqlのTimeはクライアント側の経過時間。画面の応答時間ではない。
\timing on
\echo '計測1'
SELECT id, title, popularity_score FROM ranking_books
ORDER BY popularity_score DESC, id ASC LIMIT 20;
\echo '計測2'
\g
\echo '計測3'
\g
\echo '計測4'
\g
\echo '計測5'
\g
\timing off
-- 実行計画の観察は5回の通常実行と分ける。
\echo '計測後の実行計画'
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT id, title, popularity_score FROM ranking_books
ORDER BY popularity_score DESC, id ASC LIMIT 20;
ROLLBACK;
