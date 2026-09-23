\pset pager off
\echo '--- 8. 後片付け: 取り消した追加の跡を片付ける前'
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size FROM pg_class WHERE relname IN ('books', 'books_pkey', 'books_title_idx') ORDER BY relname;
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'books';
VACUUM books;
ANALYZE books;
\echo '--- 8. 片付けた後'
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size FROM pg_class WHERE relname IN ('books', 'books_pkey', 'books_title_idx') ORDER BY relname;
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'books';
\echo '--- 8. 題名検索の全件読み（第2章と同じページ数に戻っているか）'
EXPLAIN ANALYZE SELECT * FROM books WHERE id = 42 OR id = 43;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM books;
