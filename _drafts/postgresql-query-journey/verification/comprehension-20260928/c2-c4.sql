\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
-- C2: Index の数で、10万件の追加がどれだけ重くなるか
DROP TABLE IF EXISTS c2_rr;
CREATE TABLE c2_rr (book_id bigint NOT NULL, finished_at timestamp NOT NULL);
\echo '--- index 0'
EXPLAIN (ANALYZE, WAL, BUFFERS, COSTS OFF, SUMMARY ON) INSERT INTO c2_rr SELECT book_id, finished_at FROM reading_records LIMIT 100000;
TRUNCATE c2_rr;
CREATE INDEX c2_idx1 ON c2_rr (finished_at DESC, book_id);
\echo '--- index 1'
EXPLAIN (ANALYZE, WAL, BUFFERS, COSTS OFF, SUMMARY ON) INSERT INTO c2_rr SELECT book_id, finished_at FROM reading_records LIMIT 100000;
TRUNCATE c2_rr;
CREATE INDEX c2_idx2 ON c2_rr (book_id, finished_at);
\echo '--- index 2'
EXPLAIN (ANALYZE, WAL, BUFFERS, COSTS OFF, SUMMARY ON) INSERT INTO c2_rr SELECT book_id, finished_at FROM reading_records LIMIT 100000;
DROP TABLE c2_rr;
-- C4: VACUUM でファイルが縮む場合と縮まない場合
DROP TABLE IF EXISTS c4_t;
CREATE TABLE c4_t AS SELECT g AS id, repeat('x', 100) AS pad FROM generate_series(1, 100000) g;
SELECT 'before' AS step, pg_relation_size('c4_t') / 8192 AS pages;
DELETE FROM c4_t WHERE id <= 50000;
VACUUM c4_t;
SELECT 'delete front half + VACUUM' AS step, pg_relation_size('c4_t') / 8192 AS pages;
DELETE FROM c4_t WHERE id > 75000;
VACUUM c4_t;
SELECT 'delete back quarter + VACUUM' AS step, pg_relation_size('c4_t') / 8192 AS pages;
VACUUM FULL c4_t;
SELECT 'VACUUM FULL' AS step, pg_relation_size('c4_t') / 8192 AS pages;
DROP TABLE c4_t;
