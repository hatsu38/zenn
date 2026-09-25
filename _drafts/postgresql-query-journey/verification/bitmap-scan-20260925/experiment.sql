-- Bitmap Index Scan / Bitmap Heap Scan の出現条件と、可視性マップ・WAL の観察 (2026-09-25)
-- lab: postgresql-structures-lab の db (PostgreSQL 18.6)。Index はトランザクション内に作り ROLLBACK で消す。
BEGIN;
SET LOCAL max_parallel_workers_per_gather = 0;
SET LOCAL jit = off;
SET LOCAL work_mem = '4MB';
SELECT version();
SELECT count(*), min(finished_at), max(finished_at) FROM reading_records;
CREATE INDEX reading_records_finished_at_idx ON reading_records (finished_at);
ANALYZE reading_records;
SELECT attname, correlation, n_distinct FROM pg_stats WHERE tablename = 'reading_records' AND attname IN ('finished_at', 'book_id');

\echo '=== A. 序章のランキングSQL (1週間 = 499,998件, 25%)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title ORDER BY read_count DESC, b.id ASC LIMIT 20;

\echo '=== B. 期間を狭める: 1日 / 1時間 / 1分 (読了記録のみ, book_id を返すので heap が要る)'
EXPLAIN (ANALYZE, BUFFERS, COSTS ON, TIMING OFF, SUMMARY OFF)
SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
EXPLAIN (ANALYZE, BUFFERS, COSTS ON, TIMING OFF, SUMMARY OFF)
SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20 12:00' AND r.finished_at < timestamp '2026-09-20 13:00';
EXPLAIN (ANALYZE, BUFFERS, COSTS ON, TIMING OFF, SUMMARY OFF)
SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20 12:00' AND r.finished_at < timestamp '2026-09-20 12:01';

\echo '=== C. コスト比較 (1週間): Bitmap / Seq Scan / Index Scan'
EXPLAIN (COSTS ON) SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
SET LOCAL enable_bitmapscan = off;
EXPLAIN (COSTS ON) SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS ON) SELECT book_id FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
SET LOCAL enable_bitmapscan = on;
SET LOCAL enable_seqscan = on;

\echo '=== D. lossy ビットマップ: work_mem=64kB + enable_seqscan=off'
SET LOCAL work_mem = '64kB';
SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(DISTINCT book_id) FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
SET LOCAL work_mem = '4MB';
SET LOCAL enable_seqscan = on;

\echo '=== E. 可視性マップ: Index Only Scan の Heap Fetches が UPDATE 後に増える'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(*) FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
\echo '--- UPDATE を EXPLAIN (ANALYZE, WAL) で観察'
EXPLAIN (ANALYZE, BUFFERS, WAL, COSTS OFF, TIMING OFF, SUMMARY OFF)
UPDATE reading_records SET finished_at = finished_at + interval '1 second'
WHERE finished_at >= timestamp '2026-09-20 12:00' AND finished_at < timestamp '2026-09-20 12:10';
\echo '--- 同じ SELECT を再実行 (VACUUM 前)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(*) FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
\echo '--- 参考: SELECT が書く WAL'
EXPLAIN (ANALYZE, WAL, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(*) FROM reading_records r WHERE r.finished_at >= timestamp '2026-09-20' AND r.finished_at < timestamp '2026-09-21';
ROLLBACK;
