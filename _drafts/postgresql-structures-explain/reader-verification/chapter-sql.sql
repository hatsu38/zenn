\set ON_ERROR_STOP on

\pset pager off

SELECT version();

\echo '01-explain-basics'



\set ON_ERROR_STOP on
\pset pager off
SELECT version();


CREATE TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
CREATE TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
);
INSERT INTO books
SELECT n, '実験用の本 ' || n FROM generate_series(1, 1000) AS n;
INSERT INTO reading_records
SELECT ((n::bigint * 7919) % 1000) + 1,
       timestamp '2026-08-24'
         + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, 20000) AS n;
ANALYZE books;
ANALYZE reading_records;
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;


EXPLAIN
SELECT id, title FROM books WHERE title = '実験用の本 42';


EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';


EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE id = 42;


\echo '02-process-and-execution'

SELECT pg_backend_pid();


SELECT pid, state, query
FROM pg_stat_activity
WHERE datname = current_database();


EXPLAIN
SELECT id, title FROM books ORDER BY title LIMIT 3;


\echo '03-pages-and-storage'

SELECT pg_relation_filepath('books');
SELECT pg_size_pretty(pg_relation_size('books')) AS table_size,
       pg_size_pretty(pg_total_relation_size('books')) AS total_size;
SHOW block_size;


SELECT id, ctid, title
FROM books ORDER BY id LIMIT 8;


BEGIN;
CREATE TABLE size_short AS
SELECT n AS id, repeat('a', 10) AS note
FROM generate_series(1, 1000) AS n;
CREATE TABLE size_long AS
SELECT n AS id, repeat('a', 200) AS note
FROM generate_series(1, 1000) AS n;
SELECT pg_relation_size('size_short') AS short_bytes,
       pg_relation_size('size_long') AS long_bytes;
ROLLBACK;


\echo '04-memory-and-buffers'

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';


SHOW shared_buffers;
SHOW work_mem;
SHOW temp_buffers;
SHOW maintenance_work_mem;


\echo '05-linear-search'

SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';


SELECT count(*) FROM books;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';


INSERT INTO books
SELECT n, '実験用の本 ' || n
FROM generate_series(1001, 100000) AS n
ON CONFLICT (id) DO NOTHING;
ANALYZE books;


INSERT INTO books
SELECT n, '実験用の本 ' || n
FROM generate_series(100001, 1000000) AS n
ON CONFLICT (id) DO NOTHING;
ANALYZE books;


EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books
WHERE title = '実験用の本 42'
LIMIT 1;


\echo '06-btree-index'

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';


CREATE INDEX books_title_idx ON books (title);
ANALYZE books;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';


SELECT pg_size_pretty(pg_relation_size('books_title_idx'));


EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE id BETWEEN 400000 AND 400010;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE id BETWEEN 1 AND 900000;


\echo '07-sort'

SELECT book_id, finished_at
FROM reading_records
ORDER BY finished_at DESC, book_id ASC;


TRUNCATE reading_records;
INSERT INTO reading_records
SELECT ((n::bigint * 7919) % 1000000) + 1,
       timestamp '2026-08-24'
         + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, 2000000) AS n;
ANALYZE reading_records;
SELECT count(*) FROM reading_records;


SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '64MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC;


SET work_mem = '64kB';


SET work_mem = '4MB';


SET work_mem='64kB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC;


SET work_mem='4MB';

\echo '08-top-n-heap'

SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC
LIMIT 20;


CREATE INDEX reading_records_order_idx
ON reading_records (finished_at DESC, book_id ASC);
ANALYZE reading_records;


EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC
LIMIT 20;


\echo '09-join'

EXPLAIN (ANALYZE, BUFFERS)
SELECT r.book_id, b.title, r.finished_at
FROM (
  SELECT book_id, finished_at FROM reading_records
  ORDER BY finished_at DESC, book_id ASC LIMIT 20
) AS r
JOIN books AS b ON b.id = r.book_id
ORDER BY r.finished_at DESC, r.book_id ASC;


EXPLAIN (ANALYZE, BUFFERS)
SELECT r.book_id, b.title
FROM reading_records AS r
JOIN books AS b ON b.id = r.book_id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';


BEGIN;
SET LOCAL enable_hashjoin = off;
SET LOCAL enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, r.finished_at
FROM books AS b JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id <= 100;
ROLLBACK;


EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, count(*) AS read_count
FROM reading_records GROUP BY book_id;


SHOW work_mem;
SHOW hash_mem_multiplier;


BEGIN;

SET LOCAL work_mem='64kB';

EXPLAIN (ANALYZE, BUFFERS) SELECT book_id,count(*) FROM reading_records GROUP BY book_id;

ROLLBACK;

\echo '10-planner-and-statistics'

BEGIN;
CREATE TABLE stats_demo AS
SELECT n AS id,
       CASE WHEN n <= 9000 THEN 'popular' ELSE 'rare' END AS category
FROM generate_series(1, 10000) AS n;
CREATE INDEX stats_demo_category_idx ON stats_demo (category);
ANALYZE stats_demo;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'popular';
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';


SELECT attname, n_distinct, most_common_vals, most_common_freqs,
       histogram_bounds
FROM pg_stats
WHERE schemaname = current_schema() AND tablename = 'stats_demo';


UPDATE stats_demo SET category = 'rare' WHERE id <= 8000;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';
ANALYZE stats_demo;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';
ROLLBACK;


\echo '12-ranking-revisited'

SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;


CREATE TEMP VIEW ranking_before AS
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;


BEGIN;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
ROLLBACK;


CREATE TEMP VIEW ranking_after AS
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

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_after;


SELECT count(*) AS records_without_book
FROM reading_records AS r
WHERE NOT EXISTS (SELECT 1 FROM books AS b WHERE b.id = r.book_id);


SELECT count(*) AS differing_rows FROM (
  (SELECT * FROM ranking_before EXCEPT ALL SELECT * FROM ranking_after)
  UNION ALL
  (SELECT * FROM ranking_after EXCEPT ALL SELECT * FROM ranking_before)
) AS differences;


\timing on
CREATE TABLE weekly_read_counts AS
SELECT book_id, count(*) AS read_count
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
GROUP BY book_id;
CREATE INDEX weekly_read_counts_order_idx
ON weekly_read_counts (read_count DESC, book_id ASC);
ANALYZE weekly_read_counts;

EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, w.read_count
FROM weekly_read_counts AS w JOIN books AS b ON b.id = w.book_id
ORDER BY w.read_count DESC, w.book_id ASC LIMIT 20;
