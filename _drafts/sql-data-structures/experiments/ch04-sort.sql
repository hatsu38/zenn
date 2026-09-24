\pset pager off
SELECT version();
SHOW work_mem;
SHOW shared_buffers;

\echo '--- 0. いまの読了記録'
SELECT count(*) AS record_count FROM reading_records;

\echo '--- 1. 読了記録を2,000万件にする（いまの2万件は空にしてから、序章と同じ式で作り直す）'
TRUNCATE reading_records;
INSERT INTO reading_records
SELECT ((n::bigint * 7919) % 1000000) + 1,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, 20000000) AS n;
ANALYZE reading_records;
SELECT count(*) AS record_count FROM reading_records;
SELECT relpages, reltuples::bigint AS reltuples, pg_size_pretty(pg_relation_size('reading_records')) AS size
FROM pg_class WHERE relname = 'reading_records';

\echo '--- 2. 1時間分を新しい順に並べる（1回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20 12:00' AND finished_at < timestamp '2026-09-20 13:00' ORDER BY finished_at DESC;
\echo '--- 2. 1時間分（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20 12:00' AND finished_at < timestamp '2026-09-20 13:00' ORDER BY finished_at DESC;
\echo '--- 2. 1時間分（3回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20 12:00' AND finished_at < timestamp '2026-09-20 13:00' ORDER BY finished_at DESC;

\echo '--- 3. 1日分を新しい順に並べる（1回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 3. 1日分（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 3. 1日分（3回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;

\echo '--- 4. 1週間分を新しい順に並べる（1回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 4. 1週間分（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 4. 1週間分（3回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;

\echo '--- 5. work_mem を 1GB にして 1週間分（この接続だけ）'
SET work_mem = '1GB';
SHOW work_mem;
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 5. 1GB（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
RESET work_mem;
SHOW work_mem;

\echo '--- 6. 目録は並び順を持っている（books を番号順、題名順に 20 冊）'
EXPLAIN ANALYZE SELECT * FROM books ORDER BY id LIMIT 20;
EXPLAIN ANALYZE SELECT * FROM books ORDER BY title LIMIT 20;

\echo '--- 7. 参考: 並べ替えなしで 1週間分を読むだけ'
EXPLAIN ANALYZE SELECT count(*) FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21';
