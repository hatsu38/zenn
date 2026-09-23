\pset pager off
SHOW work_mem;

\echo '--- 1. 1週間分を新しい順に 20 件（1回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 20;
\echo '--- 1. 20 件（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 20;
\echo '--- 1. 20 件（3回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 20;

\echo '--- 2. LIMIT 1000'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 1000;
\echo '--- 2. LIMIT 100000'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 100000;
\echo '--- 2. LIMIT 1000000'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 1000000;

\echo '--- 3. 全 2,000 万件から新しい順に 20 件'
EXPLAIN ANALYZE SELECT * FROM reading_records ORDER BY finished_at DESC LIMIT 20;

\timing on
\echo '--- 4. 読了日時に目録を作る'
CREATE INDEX reading_records_finished_at_idx ON reading_records (finished_at);
\timing off
SELECT relname, relpages, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class WHERE relname IN ('reading_records', 'reading_records_finished_at_idx') ORDER BY relname;
SELECT root, level FROM bt_metap('reading_records_finished_at_idx');

\echo '--- 5. 目録あり: 全件から新しい順に 20 件（1回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records ORDER BY finished_at DESC LIMIT 20;
\echo '--- 5. 20 件（2回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records ORDER BY finished_at DESC LIMIT 20;
\echo '--- 5. 20 件（3回目）'
EXPLAIN ANALYZE SELECT * FROM reading_records ORDER BY finished_at DESC LIMIT 20;
\echo '--- 5. 目録あり: 1週間分から新しい順に 20 件'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC LIMIT 20;

\echo '--- 6. 目録あり: 第4章の 1週間分を全部並べる SQL（副作用の観察）'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-14' AND finished_at < timestamp '2026-09-21' ORDER BY finished_at DESC;
\echo '--- 6. 目録あり: 1時間分を全部並べる'
EXPLAIN ANALYZE SELECT * FROM reading_records WHERE finished_at >= timestamp '2026-09-20 12:00' AND finished_at < timestamp '2026-09-20 13:00' ORDER BY finished_at DESC;
