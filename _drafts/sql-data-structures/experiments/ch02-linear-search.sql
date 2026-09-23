\pset pager off
SELECT version();
SHOW max_parallel_workers_per_gather;
SHOW jit;
SHOW work_mem;

\echo '--- 0. いまの本の冊数と、題名検索（1,000冊）'
SELECT count(*) AS book_count FROM books;
SELECT relpages, reltuples::bigint AS reltuples, pg_size_pretty(pg_relation_size('books')) AS size FROM pg_class WHERE relname = 'books';
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';

\echo '--- 1. 本を10万冊に増やす'
INSERT INTO books
SELECT n, '実験用の本 ' || n
FROM generate_series(1001, 100000) AS n;
ANALYZE books;
SELECT count(*) AS book_count FROM books;
SELECT relpages, reltuples::bigint AS reltuples, pg_size_pretty(pg_relation_size('books')) AS size FROM pg_class WHERE relname = 'books';
\echo '--- 1. 題名検索（10万冊、1回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 1. 題名検索（10万冊、2回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 1. 題名検索（10万冊、3回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';

\echo '--- 2. 見つかったところで止まれるか（10万冊、LIMIT 1、先頭近く）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42' LIMIT 1;
\echo '--- 2. LIMIT 1、真ん中'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 50000' LIMIT 1;
\echo '--- 2. LIMIT 1、末尾近く'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 99958' LIMIT 1;
\echo '--- 2. LIMIT なし、末尾近く（比較用）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 99958';

\echo '--- 3. 本を100万冊に増やす'
INSERT INTO books
SELECT n, '実験用の本 ' || n
FROM generate_series(100001, 1000000) AS n;
ANALYZE books;
SELECT count(*) AS book_count FROM books;
SELECT relpages, reltuples::bigint AS reltuples, pg_size_pretty(pg_relation_size('books')) AS size FROM pg_class WHERE relname = 'books';
\echo '--- 3. 題名検索の予定（100万冊、EXPLAIN のみ）'
EXPLAIN SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 3. 題名検索（100万冊、1回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 3. 題名検索（100万冊、2回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 3. 題名検索（100万冊、3回目）'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';

\echo '--- 4. 1ページに入っている冊数（先頭ページ）'
SELECT count(*) AS rows_in_first_page FROM books WHERE ctid >= '(0,1)' AND ctid < '(1,1)';

\echo '--- 5. 番号検索（100万冊）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 999958;

\echo '--- 6. 発展の注記用: 100万冊で LIMIT 1 を付けると、読み始めの位置が先頭とは限らない'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42' LIMIT 1;
SHOW synchronize_seqscans;
SHOW shared_buffers;
