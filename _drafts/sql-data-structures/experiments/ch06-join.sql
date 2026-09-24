\pset pager off
SHOW work_mem;
SHOW hash_mem_multiplier;

\echo '--- 1. 最近読み終えた 20 件に題名を付ける（1回目）'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id ORDER BY r.finished_at DESC LIMIT 20;
\echo '--- 1. 20 件に題名（2回目）'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id ORDER BY r.finished_at DESC LIMIT 20;
\echo '--- 1. 20 件に題名（3回目）'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id ORDER BY r.finished_at DESC LIMIT 20;

\echo '--- 2. 1週間分すべてに題名を付ける（1回目）'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
\echo '--- 2. 1週間分（2回目）'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
\echo '--- 2. 1日分に題名を付ける'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
\echo '--- 2. 1時間分に題名を付ける'
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-20 12:00' AND r.finished_at < timestamp '2026-09-20 13:00';

\echo '--- 3. Hash Join を使わせない（1日分、この接続だけ）'
SET enable_hashjoin = off;
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
\echo '--- 3. Merge Join も使わせない（1日分）'
SET enable_mergejoin = off;
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
RESET enable_hashjoin;
RESET enable_mergejoin;
SHOW enable_hashjoin;
SHOW enable_mergejoin;

\echo '--- 4. work_mem を 8MB にして Hash Join（1日分）'
SET work_mem = '8MB';
EXPLAIN ANALYZE SELECT r.finished_at, b.title FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
RESET work_mem;
SHOW work_mem;

\echo '--- 5. 本ごとに数える（GROUP BY、1週間分）'
EXPLAIN ANALYZE SELECT book_id, count(*) AS read_count FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' GROUP BY book_id;

\echo '--- 6. 1冊の本の読了記録（book_id に目録なし）'
EXPLAIN ANALYZE SELECT r.finished_at FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE b.title = '実験用の本 42' ORDER BY r.finished_at DESC;
\timing on
\echo '--- 6. 本の番号に目録を作る'
CREATE INDEX reading_records_book_id_idx ON reading_records (book_id);
\timing off
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname LIKE 'reading_records%' ORDER BY relname;
\echo '--- 6. 目録あり: 1冊の本の読了記録（1回目）'
EXPLAIN ANALYZE SELECT r.finished_at FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE b.title = '実験用の本 42' ORDER BY r.finished_at DESC;
\echo '--- 6. 目録あり（2回目）'
EXPLAIN ANALYZE SELECT r.finished_at FROM reading_records AS r JOIN books AS b ON b.id = r.book_id WHERE b.title = '実験用の本 42' ORDER BY r.finished_at DESC;
