\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
CREATE TABLE books_observation (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
INSERT INTO books_observation
SELECT id, title FROM books WHERE id BETWEEN 1 AND 1000 ORDER BY id;
ANALYZE books_observation;
SELECT count(*) FROM books_observation;
\echo block-0
SELECT count(*) FROM books_observation;
\echo block-4
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
SELECT * FROM pg_buffercache_evict_relation('books_observation');
\echo block-6
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books_observation WHERE title = '実験用の本 42';
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books_observation WHERE title = '実験用の本 42';
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books_observation WHERE title = '実験用の本 42';
\echo block-10
SHOW shared_buffers;
\echo block-12
SHOW work_mem;
\echo block-14
SHOW temp_buffers;
\echo block-16
SHOW maintenance_work_mem;
\echo block-18
DROP TABLE books_observation;
SELECT to_regclass('books_observation') IS NULL AS observation_removed, (SELECT count(*) FROM books) AS books_count, to_regclass('books_title_idx') IS NOT NULL AS title_index_kept;
