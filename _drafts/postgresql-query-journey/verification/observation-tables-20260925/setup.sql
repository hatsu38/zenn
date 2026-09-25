\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT version();
CREATE TABLE books (id bigint PRIMARY KEY, title text NOT NULL);
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1, 1000000) AS n;
CREATE INDEX books_title_idx ON books (title);
ANALYZE books;
