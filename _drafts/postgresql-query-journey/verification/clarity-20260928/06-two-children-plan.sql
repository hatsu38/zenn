-- 第6章「子が二つある計画」に載せる小さな計画の採取（2026-09-28）
-- 第6章の時点では reading_records に Index がない。lab は第12章まで進めた状態で、
-- 第8章の reading_records_order_idx があるため、BEGIN〜ROLLBACK の中で消してから測る。
-- 本42と本43の読了記録に題名を付ける。子が二つある Hash Join になるかを確かめる。
SELECT version();
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SET lock_timeout = '3s';
BEGIN;
DROP INDEX reading_records_order_idx;
SELECT indexname FROM pg_indexes WHERE tablename IN ('books','reading_records') ORDER BY 1;
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, r.finished_at
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id IN (42, 43);
-- 2回目（計画が変わらないかの確認）
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, r.finished_at
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id IN (42, 43);
-- 結果の3件
SELECT b.title, r.finished_at
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id IN (42, 43);
-- 参考: 本42だけにすると Nested Loop になる
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, r.finished_at
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id = 42;
ROLLBACK;
SELECT indexname FROM pg_indexes WHERE tablename = 'reading_records';
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
