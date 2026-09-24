-- 第4章の観察用の表と行幅実験で、ページごとに何行入っているかを ctid で数える（2026-09-25）
-- 図 03-pages-and-rows と 03-row-width の数値の出典。最後に ROLLBACK するので何も残らない
BEGIN;
CREATE SCHEMA book_observation;
CREATE TABLE book_observation.books
  (LIKE public.books INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE book_observation.books ADD PRIMARY KEY (id);
INSERT INTO book_observation.books
SELECT id, title FROM public.books WHERE id BETWEEN 1 AND 1000;
SET LOCAL search_path = book_observation, public;
ANALYZE books;
SELECT pg_relation_size('books') AS table_bytes,
       pg_relation_size('books') / current_setting('block_size')::int AS pages;
SELECT (ctid::text::point)[0]::int AS page, count(*) AS rows_in_page,
       min(id) AS first_id, max(id) AS last_id
FROM books GROUP BY 1 ORDER BY 1;
SELECT id, ctid FROM books WHERE id IN (1, 5, 136, 137, 1000) ORDER BY id;
SAVEPOINT row_width;
CREATE TABLE size_short AS
SELECT n AS id, repeat('a', 10) AS note
FROM generate_series(1, 1000) AS n;
CREATE TABLE size_long AS
SELECT n AS id, repeat('a', 200) AS note
FROM generate_series(1, 1000) AS n;
SELECT pg_relation_size('size_short') AS short_bytes,
       pg_relation_size('size_long') AS long_bytes;
SELECT (ctid::text::point)[0]::int AS page, count(*) AS rows_in_page
FROM size_short GROUP BY 1 ORDER BY 1;
SELECT (ctid::text::point)[0]::int AS page, count(*) AS rows_in_page
FROM size_long GROUP BY 1 ORDER BY 1;
ROLLBACK TO SAVEPOINT row_width;
ROLLBACK;
SELECT count(*) AS leftover_schema FROM pg_namespace WHERE nspname = 'book_observation';
