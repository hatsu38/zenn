\pset pager off
SELECT version();
SHOW max_parallel_workers_per_gather;
SHOW work_mem;

\echo '--- 0. 表と主キーの目録の大きさ'
SELECT count(*) AS book_count FROM books;
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname IN ('books', 'books_pkey') ORDER BY relname;

\echo '--- 1. 目録の中を見る道具を入れる'
CREATE EXTENSION IF NOT EXISTS pageinspect;

\echo '--- 1. 目録の案内ページ（段数）'
SELECT root, level FROM bt_metap('books_pkey');
\echo '--- 1. 根のページの中身'
SELECT type, live_items, btpo_level FROM bt_page_stats('books_pkey', (SELECT root FROM bt_metap('books_pkey')));
\echo '--- 1. 段ごとのページ数'
SELECT btpo_level AS level, count(*) AS pages
FROM (
  SELECT (bt_page_stats('books_pkey', g)).btpo_level
  FROM generate_series(1, (SELECT relpages FROM pg_class WHERE relname = 'books_pkey') - 1) AS g
) AS s
GROUP BY btpo_level ORDER BY btpo_level DESC;

\echo '--- 2. 番号検索（100万冊、1回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
\echo '--- 2. 番号検索（100万冊、2回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
\echo '--- 2. 番号検索（100万冊、3回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
\echo '--- 2. 番号検索（末尾近く）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 999958;

\echo '--- 3. 小さい表の目録の段数（1,000冊と10万冊、一時テーブル）'
CREATE TEMP TABLE books_small AS SELECT * FROM books WHERE id <= 1000;
ALTER TABLE books_small ADD PRIMARY KEY (id);
CREATE TEMP TABLE books_mid AS SELECT * FROM books WHERE id <= 100000;
ALTER TABLE books_mid ADD PRIMARY KEY (id);
SELECT 'books_small_pkey' AS index_name, level, (SELECT relpages FROM pg_class WHERE relname = 'books_small_pkey') AS relpages FROM bt_metap('books_small_pkey')
UNION ALL
SELECT 'books_mid_pkey', level, (SELECT relpages FROM pg_class WHERE relname = 'books_mid_pkey') FROM bt_metap('books_mid_pkey')
UNION ALL
SELECT 'books_pkey', level, (SELECT relpages FROM pg_class WHERE relname = 'books_pkey') FROM bt_metap('books_pkey');

\timing on
\echo '--- 4. 目録がないときの追加の時間（1万冊、3回、ROLLBACK）'
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;

\echo '--- 5. 題名に目録を作る'
CREATE INDEX books_title_idx ON books (title);
\timing off
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname IN ('books', 'books_pkey', 'books_title_idx') ORDER BY relname;
SELECT root, level FROM bt_metap('books_title_idx');

\echo '--- 5. 題名検索（1回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 5. 題名検索（2回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 5. 題名検索（3回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 5. 題名検索（真ん中）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 500000';
\echo '--- 5. 題名検索（末尾近く）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 999958';

\timing on
\echo '--- 6. 目録があるときの追加の時間（1万冊、3回、ROLLBACK）'
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;
BEGIN;
INSERT INTO books SELECT n, '実験用の本 ' || n FROM generate_series(1000001, 1010000) AS n;
ROLLBACK;
\timing off

\echo '--- 7. 発展の注記用: 前方一致では目録が使われるか'
EXPLAIN ANALYZE SELECT * FROM books WHERE title LIKE '実験用の本 4295%';
SHOW lc_collate;
SELECT datcollate FROM pg_database WHERE datname = 'reading_log';

SELECT count(*) AS book_count FROM books;
