-- 第3章に載せる Bitmap Scan の実測（2026-09-25）。books と既存の books_title_idx だけを使う。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT attname, correlation FROM pg_stats WHERE tablename = 'books' AND attname IN ('id', 'title');
\echo '=== 題名の並び順（Index の順）で先頭の8冊'
SELECT id, title FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5' ORDER BY title LIMIT 8;
\echo '=== 題名が「実験用の本 4」で始まる本（111,111冊）'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5';
\echo '=== 同じ範囲を Index Scan に限定'
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5';
\echo '=== 同じ範囲を Seq Scan に限定'
SET enable_indexscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5';
RESET enable_bitmapscan;
RESET enable_indexscan;
\echo '=== 参考: 範囲に入る行が載っているページ数'
SELECT count(DISTINCT (ctid::text::point)[0]) AS pages FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5';
