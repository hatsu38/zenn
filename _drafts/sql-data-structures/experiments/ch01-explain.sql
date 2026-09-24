\pset pager off
SELECT version();
SHOW work_mem;
SHOW max_parallel_workers_per_gather;
SHOW jit;
SELECT relname, relpages, reltuples::bigint AS reltuples
FROM pg_class
WHERE relname IN ('books', 'books_pkey', 'reading_records')
ORDER BY relname;

\echo '--- 1. EXPLAIN 題名で1冊'
EXPLAIN SELECT * FROM books WHERE title = '実験用の本 42';

\echo '--- 2. EXPLAIN ANALYZE 題名で1冊 (1回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 2. EXPLAIN ANALYZE 題名で1冊 (2回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 2. EXPLAIN ANALYZE 題名で1冊 (3回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42';

\echo '--- 3. EXPLAIN 番号で1冊'
EXPLAIN SELECT * FROM books WHERE id = 42;

\echo '--- 4. EXPLAIN ANALYZE 番号で1冊 (1回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
\echo '--- 4. EXPLAIN ANALYZE 番号で1冊 (2回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;
\echo '--- 4. EXPLAIN ANALYZE 番号で1冊 (3回目)'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42;

\echo '--- 参考. 通常の SELECT の結果'
SELECT * FROM books WHERE title = '実験用の本 42';
SELECT * FROM books WHERE id = 42;

\echo '--- 参考. EXPLAIN が実行しないことの確認（ANALYZE なしで INSERT を EXPLAIN しても行数は増えない）'
SELECT count(*) AS before_count FROM books;
EXPLAIN INSERT INTO books VALUES (1001, '実験用の本 1001');
SELECT count(*) AS after_count FROM books;
