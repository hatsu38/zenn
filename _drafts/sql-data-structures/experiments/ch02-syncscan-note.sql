\pset pager off
-- 発展の注記用: 100万冊で LIMIT 1 を付けた題名検索の読み始め位置が、直前の全件読みの影響で変わることの記録
-- 全件読みを 1 回挟んでから LIMIT 1 を打つ、を 3 回繰り返す
\echo '--- 全件読み A'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM books WHERE title = '実験用の本 500000';
\echo '--- 直後の LIMIT 1（先頭近くの本）A'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42' LIMIT 1;
\echo '--- 全件読み B'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM books WHERE title = '実験用の本 999958';
\echo '--- 直後の LIMIT 1（先頭近くの本）B'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42' LIMIT 1;
\echo '--- 全件読み C'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM books WHERE title = '実験用の本 42';
\echo '--- 直後の LIMIT 1（先頭近くの本）C'
EXPLAIN ANALYZE SELECT * FROM books WHERE title = '実験用の本 42' LIMIT 1;
SHOW synchronize_seqscans;
SHOW shared_buffers;
SELECT pg_size_pretty(pg_relation_size('books')) AS books_size;
