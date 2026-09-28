-- 第7章の外部ソート（work_mem = 64kB）で、まとまり（run）がいくつでき、何個ずつ合流したかを trace_sort で確かめる。
-- 第8章で作る reading_records_order_idx が lab に残っているため、Index を使う計画を切って、第7章と同じ Seq Scan → Sort の計画にする（Index は消さない）。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT version();
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;
SET work_mem = '64kB';
SET trace_sort = on;
SET client_min_messages = log;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC;
RESET client_min_messages;
RESET trace_sort;
SET work_mem = '4MB';
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
