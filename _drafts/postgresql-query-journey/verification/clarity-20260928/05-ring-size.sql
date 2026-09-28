-- 第5章のリングバッファの大きさを確かめる（2026-09-28）
-- 本のテーブルは使わず、books を写した使い捨てのテーブル ring_probe で測り、最後に消す。
-- ソース（REL_18_STABLE の freelist.c）では、BAS_BULKREAD の輪は 256kB に
-- 8kB × io_combine_limit × effective_io_concurrency を足し、1プロセスが固定できるページ数の上限で抑える。
SELECT version();
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SHOW shared_buffers;
SHOW io_combine_limit;
SHOW effective_io_concurrency;
SHOW max_connections;
CREATE TABLE ring_probe AS SELECT * FROM books;
SELECT pg_relation_size('ring_probe') / 8192 AS pages;
SELECT buffers_evicted FROM pg_buffercache_evict_relation('ring_probe');
-- 共有バッファに残っている ring_probe の本体のページ数（追い出した直後）
SELECT count(*) FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relname = 'ring_probe' AND b.relforknumber = 0 AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database());
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM ring_probe;
-- 1回読んだ後に残っているページ数（輪の大きさの目安）
SELECT count(*) FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relname = 'ring_probe' AND b.relforknumber = 0 AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database());
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM ring_probe;
SELECT count(*) FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE c.relname = 'ring_probe' AND b.relforknumber = 0 AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database());
DROP TABLE ring_probe;
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
