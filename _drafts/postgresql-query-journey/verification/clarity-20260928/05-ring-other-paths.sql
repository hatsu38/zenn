-- 第5章：輪を通らずに共有バッファへ入ったページが、次の Seq Scan で hit になるかを確かめる（2026-09-29）
-- 本のテーブルは使わず、books を写した使い捨てのテーブル ring_path_probe で測り、最後に消す。
-- ソース（REL_18_STABLE）での根拠:
--   heapam.c initscan: テーブルが NBuffers/4 を超え、SO_ALLOW_STRAT のとき BAS_BULKREAD の輪を使う。
--   tableam.h table_beginscan_bm: Bitmap Heap Scan の flags に SO_ALLOW_STRAT がない（輪を使わない）。
--   heapam_handler.c: Index Scan のテーブル読みは ReleaseAndReadBuffer（輪を使わない）。
--   bufmgr.c BufferAlloc: 共有バッファにすでにあるページは PinBuffer で hit になり、StrategyGetBuffer（輪）を通らない。
SELECT version();
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
CREATE TABLE ring_path_probe AS SELECT * FROM books;
CREATE INDEX ring_path_probe_id_idx ON ring_path_probe (id);
VACUUM ring_path_probe;
SELECT pg_relation_size('ring_path_probe') / 8192 AS pages;
SELECT buffers_evicted FROM pg_buffercache_evict_relation('ring_path_probe');
-- テーブルの本体のページで、共有バッファにあるものを数える
CREATE TEMP VIEW probe_cached AS
SELECT count(*) AS cached_pages FROM pg_buffercache b
WHERE b.relfilenode = pg_relation_filenode('ring_path_probe') AND b.relforknumber = 0
  AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database());
SELECT * FROM probe_cached;
-- ① 全件読む（輪を通る）
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(*) FROM ring_path_probe;
SELECT * FROM probe_cached;
-- ② もう一度全件読む（輪に残った分だけ hit）
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(*) FROM ring_path_probe;
SELECT * FROM probe_cached;
-- ③ Index Scan で番号 1〜100000 を読む（テーブルのページは輪を通らずに入る）
SET enable_bitmapscan = off;
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(title) FROM ring_path_probe WHERE id BETWEEN 1 AND 100000;
RESET enable_bitmapscan;
RESET enable_seqscan;
SELECT * FROM probe_cached;
-- ④ もう一度全件読む（③で入ったページも hit になるか）
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(*) FROM ring_path_probe;
SELECT * FROM probe_cached;
-- ⑤ Bitmap Heap Scan で番号 500001〜600000 を読んでから、もう一度全件読む
SET enable_indexscan = off;
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(title) FROM ring_path_probe WHERE id BETWEEN 500001 AND 600000;
RESET enable_indexscan;
RESET enable_seqscan;
SELECT * FROM probe_cached;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(*) FROM ring_path_probe;
SELECT * FROM probe_cached;
DROP VIEW probe_cached;
DROP TABLE ring_path_probe;
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
