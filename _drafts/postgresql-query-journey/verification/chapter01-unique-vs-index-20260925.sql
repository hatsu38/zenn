\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SET synchronize_seqscans = off;

SELECT version();
\d public.books

-- 公開用の books には触れず、別スキーマに同じ100万冊を作って最後に ROLLBACK する
BEGIN;
CREATE SCHEMA uq_check;
SET LOCAL search_path = uq_check;
CREATE TABLE books (id bigint PRIMARY KEY, title text NOT NULL);
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1, 1000000) AS n;
ANALYZE books;

-- データ上は、題名はすでに全部ちがう
SELECT count(*) AS books, count(DISTINCT title) AS distinct_titles FROM books;
SELECT n_distinct FROM pg_stats
WHERE schemaname = 'uq_check' AND tablename = 'books' AND attname = 'title';

\echo '=== A: 題名に約束なし・題名のIndexなし（第1章と同じ） ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE title = '実験用の本 42';

\echo '=== B: 主キー（一意）の番号で探す。ただしIndexを使わせない ==='
SET LOCAL enable_indexscan = off;
SET LOCAL enable_bitmapscan = off;
SET LOCAL enable_indexonlyscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE id = 42;

\echo '=== C: 題名に一意の約束（UNIQUE）を付ける。Indexはまだ使わせない ==='
ALTER TABLE books ADD CONSTRAINT books_title_key UNIQUE (title);
\d books
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE title = '実験用の本 42';

\echo '=== D: 一意の約束のまま、Indexを使ってよいことにする（LIMITなし） ==='
SET LOCAL enable_indexscan = on;
SET LOCAL enable_bitmapscan = on;
SET LOCAL enable_indexonlyscan = on;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE title = '実験用の本 42';

\echo '=== E: 約束を外し、一意でないふつうのIndexにする（LIMITなし） ==='
ALTER TABLE books DROP CONSTRAINT books_title_key;
CREATE INDEX books_title_idx ON books (title);
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE title = '実験用の本 42';

ROLLBACK;

-- 後片付けの確認：uq_check スキーマが残っていないこと
SELECT count(*) AS leftover_schemas FROM pg_namespace WHERE nspname = 'uq_check';
