\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
BEGIN;
CREATE SCHEMA book_observation;
CREATE TABLE book_observation.books
  (LIKE public.books INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE book_observation.books ADD PRIMARY KEY (id);
INSERT INTO book_observation.books
SELECT id, title FROM public.books WHERE id BETWEEN 1 AND 1000;
SET LOCAL search_path = book_observation, public;
ANALYZE books;
SELECT count(*) FROM books;
SELECT pg_relation_filepath('books');
SELECT pg_size_pretty(pg_relation_size('books')) AS table_size,
       pg_size_pretty(pg_total_relation_size('books')) AS total_size;
SELECT pg_size_pretty(pg_relation_size('public.books')) AS table_size,
       pg_relation_size('public.books') / current_setting('block_size')::int AS pages;
CREATE EXTENSION IF NOT EXISTS pageinspect;
SELECT level FROM bt_metap('public.books_title_idx');
SELECT id, ctid, title
FROM books ORDER BY id LIMIT 8;
SAVEPOINT row_width;
CREATE TABLE size_short AS
SELECT n AS id, repeat('a', 10) AS note
FROM generate_series(1, 1000) AS n;
CREATE TABLE size_long AS
SELECT n AS id, repeat('a', 200) AS note
FROM generate_series(1, 1000) AS n;
SELECT pg_relation_size('size_short') AS short_bytes,
       pg_relation_size('size_long') AS long_bytes;
ROLLBACK TO SAVEPOINT row_width;
ROLLBACK;
