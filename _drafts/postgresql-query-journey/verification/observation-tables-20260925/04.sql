\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
\echo block-0
CREATE TABLE books_observation (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
INSERT INTO books_observation
SELECT id, title FROM books WHERE id BETWEEN 1 AND 1000 ORDER BY id;
ANALYZE books_observation;
SELECT count(*) FROM books_observation;
\echo block-2
SELECT pg_relation_filepath('books_observation');
\echo block-4
SELECT pg_size_pretty(pg_relation_size('books_observation')) AS table_size,
       pg_size_pretty(pg_total_relation_size('books_observation')) AS total_size;
\echo block-6
SHOW block_size;
\echo block-8
SELECT id, ctid, title
FROM books_observation ORDER BY id LIMIT 8;
SELECT (ctid::text::point)[0]::int AS page, count(*) FROM books_observation GROUP BY 1 ORDER BY 1;
\echo block-10
SELECT pg_size_pretty(pg_relation_size('public.books')) AS table_size,
       pg_relation_size('public.books') / current_setting('block_size')::int AS pages;
\echo block-12
CREATE EXTENSION IF NOT EXISTS pageinspect;
SELECT level FROM bt_metap('public.books_title_idx');
\echo block-14
CREATE TABLE size_short AS
SELECT n AS id, repeat('a', 10) AS note
FROM generate_series(1, 1000) AS n;
CREATE TABLE size_long AS
SELECT n AS id, repeat('a', 200) AS note
FROM generate_series(1, 1000) AS n;
SELECT pg_relation_size('size_short') AS short_bytes,
       pg_relation_size('size_long') AS long_bytes;
SELECT 'size_short' AS name, (ctid::text::point)[0]::int AS page, count(*) FROM size_short GROUP BY 1,2 ORDER BY 2;
SELECT 'size_long' AS name, (ctid::text::point)[0]::int AS page, count(*) FROM size_long GROUP BY 1,2 ORDER BY 2;
\echo block-16
DROP TABLE size_short, size_long;
